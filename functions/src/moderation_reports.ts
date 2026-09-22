import { createHash } from 'node:crypto';

import { DocumentData, Firestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { defineSecret, defineString } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';
import { chatParticipants, timestampValue } from './firestore_values';

const resendApiKey = defineSecret('RESEND_API_KEY');
const moderationEmail = defineString('MODERATION_EMAIL', {
  description: 'Dirección que recibirá los correos de moderación.',
});
const moderationFrom = defineString('MODERATION_FROM', {
  description: 'Remitente verificado en Resend, por ejemplo MusiLink <reports@musilink.app>.',
});

const reportReasons = new Set([
  'spam',
  'harassment',
  'sexual_content',
  'hate_speech',
  'impersonation',
  'other',
] as const);
const reportWindowMs = 60 * 60 * 1000;
const maxReportsPerWindow = 10;

export type ReportReason =
  | 'spam'
  | 'harassment'
  | 'sexual_content'
  | 'hate_speech'
  | 'impersonation'
  | 'other';

export type ReportPayload =
  | { type: 'profile'; reason: ReportReason; reportedUserId: string }
  | { type: 'message'; reason: ReportReason; chatId: string; messageId: string };

interface ModerationEmail {
  subject: string;
  text: string;
  reportType: ReportPayload['type'];
  reason: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validDocumentId(value: unknown, maxBytes = 300): value is string {
  return typeof value === 'string'
    && value.length > 0
    && value !== '.'
    && value !== '..'
    && !value.includes('/')
    && Buffer.byteLength(value, 'utf8') <= maxBytes;
}

export function parseReportPayload(value: unknown): ReportPayload {
  if (!isRecord(value) || !reportReasons.has(value.reason as ReportReason)) {
    throw new HttpsError('invalid-argument', 'A valid report reason is required.');
  }

  if (
    value.type === 'profile'
    && Object.keys(value).length === 3
    && validDocumentId(value.reportedUserId, 128)
  ) {
    return {
      type: 'profile',
      reason: value.reason as ReportReason,
      reportedUserId: value.reportedUserId,
    };
  }

  if (
    value.type === 'message'
    && Object.keys(value).length === 4
    && validDocumentId(value.chatId)
    && validDocumentId(value.messageId, 128)
  ) {
    return {
      type: 'message',
      reason: value.reason as ReportReason,
      chatId: value.chatId,
      messageId: value.messageId,
    };
  }

  throw new HttpsError('invalid-argument', 'Invalid report data.');
}

export function reportDocumentId(reporterId: string, payload: ReportPayload): string {
  const target = payload.type === 'profile'
    ? payload.reportedUserId
    : `${payload.chatId}:${payload.messageId}`;
  return createHash('sha256')
    .update(`${reporterId}:${payload.type}:${target}`)
    .digest('hex');
}

function publicProfileSnapshot(data: DocumentData | undefined): Record<string, string> {
  return {
    displayName: typeof data?.displayName === 'string' ? data.displayName : '',
    username: typeof data?.username === 'string' ? data.username : '',
  };
}

function isActiveProfile(data: DocumentData | undefined): boolean {
  return data !== undefined && data.username !== 'deleted_user';
}

function reportLimit(
  data: DocumentData | undefined,
  now: Timestamp,
): { limited: boolean; windowStart: Timestamp; count: number } {
  const windowStart = timestampValue(data?.reportWindowStart);
  const count = typeof data?.reportCount === 'number'
    && Number.isInteger(data.reportCount)
    && data.reportCount >= 0
    ? data.reportCount
    : 0;
  if (!windowStart || now.toMillis() - windowStart.toMillis() >= reportWindowMs) {
    return { limited: false, windowStart: now, count: 1 };
  }
  if (count >= maxReportsPerWindow) {
    return { limited: true, windowStart, count };
  }
  return { limited: false, windowStart, count: count + 1 };
}

function messageSnapshot(data: DocumentData): Record<string, unknown> {
  return {
    senderId: data.senderId,
    text: typeof data.text === 'string' ? data.text : '',
    type: data.type === 'track' ? 'track' : 'text',
    timestamp: timestampValue(data.timestamp) ?? null,
    ...(data.type === 'track' && isRecord(data.trackData)
      ? { trackData: data.trackData }
      : {}),
  };
}

export async function createModerationReport(
  firestore: Firestore,
  reporterId: string,
  payload: ReportPayload,
  now = Timestamp.now(),
): Promise<{ created: boolean; reportId: string; reportedUserId: string }> {
  const reportId = reportDocumentId(reporterId, payload);
  const reportRef = firestore.doc(`moderation_reports/${reportId}`);
  const reporterRef = firestore.doc(`users/${reporterId}`);
  const reporterDeletionRef = firestore.doc(`account_deletions/${reporterId}`);
  const limiterRef = firestore.doc(`rate_limits/${reporterId}`);

  return firestore.runTransaction(async (tx) => {
    const baseReads = [
      tx.get(reportRef),
      tx.get(reporterRef),
      tx.get(reporterDeletionRef),
      tx.get(limiterRef),
    ] as const;

    if (payload.type === 'profile') {
      if (payload.reportedUserId === reporterId) {
        throw new HttpsError('invalid-argument', 'You cannot report your own profile.');
      }
      const targetRef = firestore.doc(`users/${payload.reportedUserId}`);
      const [reportSnap, reporterSnap, reporterDeletionSnap, limiterSnap, targetSnap] =
        await Promise.all([...baseReads, tx.get(targetRef)]);
      if (!isActiveProfile(reporterSnap.data()) || reporterDeletionSnap.exists) {
        throw new HttpsError('failed-precondition', 'The reporter account is not active.');
      }
      if (!isActiveProfile(targetSnap.data())) {
        throw new HttpsError('not-found', 'The reported profile does not exist.');
      }
      if (reportSnap.exists) {
        return { created: false, reportId, reportedUserId: payload.reportedUserId };
      }

      const limit = reportLimit(limiterSnap.data(), now);
      if (limit.limited) {
        throw new HttpsError('resource-exhausted', 'Too many reports. Try again later.');
      }
      tx.set(limiterRef, {
        reportWindowStart: limit.windowStart,
        reportCount: limit.count,
      }, { merge: true });
      tx.create(reportRef, {
        type: payload.type,
        reason: payload.reason,
        status: 'open',
        reporterId,
        reportedUserId: payload.reportedUserId,
        reporter: publicProfileSnapshot(reporterSnap.data()),
        reportedUser: publicProfileSnapshot(targetSnap.data()),
        createdAt: now,
      });
      return { created: true, reportId, reportedUserId: payload.reportedUserId };
    }

    const chatRef = firestore.doc(`chats/${payload.chatId}`);
    const messageRef = chatRef.collection('messages').doc(payload.messageId);
    const [reportSnap, reporterSnap, reporterDeletionSnap, limiterSnap, chatSnap, messageSnap] =
      await Promise.all([...baseReads, tx.get(chatRef), tx.get(messageRef)]);
    if (!isActiveProfile(reporterSnap.data()) || reporterDeletionSnap.exists) {
      throw new HttpsError('failed-precondition', 'The reporter account is not active.');
    }
    const participants = chatParticipants(chatSnap.data());
    const message = messageSnap.data();
    if (!participants.includes(reporterId) || !message) {
      throw new HttpsError('not-found', 'The reported message does not exist.');
    }
    const reportedUserId = typeof message.senderId === 'string' ? message.senderId : '';
    if (!reportedUserId || reportedUserId === reporterId || !participants.includes(reportedUserId)) {
      throw new HttpsError('invalid-argument', 'Only messages from another participant can be reported.');
    }
    if (reportSnap.exists) return { created: false, reportId, reportedUserId };

    const targetRef = firestore.doc(`users/${reportedUserId}`);
    const targetSnap = await tx.get(targetRef);
    const limit = reportLimit(limiterSnap.data(), now);
    if (limit.limited) {
      throw new HttpsError('resource-exhausted', 'Too many reports. Try again later.');
    }
    tx.set(limiterRef, {
      reportWindowStart: limit.windowStart,
      reportCount: limit.count,
    }, { merge: true });
    tx.create(reportRef, {
      type: payload.type,
      reason: payload.reason,
      status: 'open',
      reporterId,
      reportedUserId,
      reporter: publicProfileSnapshot(reporterSnap.data()),
      reportedUser: publicProfileSnapshot(targetSnap.data()),
      chatId: payload.chatId,
      messageId: payload.messageId,
      message: messageSnapshot(message),
      createdAt: now,
    });
    return { created: true, reportId, reportedUserId };
  });
}

function displayProfile(value: unknown): string {
  if (!isRecord(value)) return '(sin datos)';
  const displayName = typeof value.displayName === 'string' ? value.displayName : '';
  const username = typeof value.username === 'string' ? value.username : '';
  return [displayName, username ? `@${username}` : ''].filter(Boolean).join(' ') || '(sin datos)';
}

export function buildModerationEmail(
  reportId: string,
  report: DocumentData,
): ModerationEmail {
  const reportType = report.type === 'message' ? 'message' : 'profile';
  const reason = typeof report.reason === 'string' ? report.reason : 'other';
  const lines = [
    'Se ha recibido una nueva denuncia en MusiLink.',
    '',
    `Tipo: ${reportType === 'message' ? 'mensaje' : 'perfil'}`,
    `Motivo: ${reason}`,
    `Denunciante: ${displayProfile(report.reporter)} (${String(report.reporterId ?? '')})`,
    `Usuario denunciado: ${displayProfile(report.reportedUser)} (${String(report.reportedUserId ?? '')})`,
    `ID de denuncia: ${reportId}`,
  ];

  if (reportType === 'message') {
    const message = isRecord(report.message) ? report.message : {};
    lines.push(
      '',
      `Chat: ${String(report.chatId ?? '')}`,
      `Mensaje: ${String(report.messageId ?? '')}`,
      `Tipo de mensaje: ${String(message.type ?? '')}`,
      'Contenido:',
      typeof message.text === 'string' ? message.text : '',
    );
  }

  lines.push(
    '',
    'Revisa el documento en Firebase Console → Firestore → moderation_reports.',
  );
  return {
    subject: reportType === 'message'
      ? '[MusiLink] Nuevo mensaje denunciado'
      : '[MusiLink] Nuevo perfil denunciado',
    text: lines.join('\n'),
    reportType,
    reason,
  };
}

export async function sendResendEmail(
  apiKey: string,
  from: string,
  to: string,
  reportId: string,
  email: ModerationEmail,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const response = await fetcher('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': `moderation-report/${reportId}`,
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: email.subject,
      text: email.text,
      tags: [
        { name: 'report_type', value: email.reportType },
        { name: 'reason', value: email.reason.replace(/[^A-Za-z0-9_-]/g, '_') },
      ],
    }),
    signal: AbortSignal.timeout(8_000),
  });
  const responseText = await response.text();
  if (!response.ok) {
    throw new Error(`Resend returned HTTP ${response.status}: ${responseText.slice(0, 500)}`);
  }
  let body: unknown;
  try {
    body = JSON.parse(responseText);
  } catch {
    throw new Error('Resend returned an invalid JSON response.');
  }
  if (!isRecord(body) || typeof body.id !== 'string' || !body.id) {
    throw new Error('Resend did not return an email ID.');
  }
  return body.id;
}

async function notifyModerator(reportId: string): Promise<void> {
  const reportRef = db.doc(`moderation_reports/${reportId}`);
  let providerMessageId: string;
  try {
    const [reportSnap, apiKey, from, to] = await Promise.all([
      reportRef.get(),
      Promise.resolve(resendApiKey.value().trim()),
      Promise.resolve(moderationFrom.value().trim()),
      Promise.resolve(moderationEmail.value().trim()),
    ]);
    const report = reportSnap.data();
    if (!report || !apiKey || !from || !to) {
      throw new Error('Resend moderation email is not fully configured.');
    }
    const email = buildModerationEmail(reportId, report);
    providerMessageId = await sendResendEmail(
      apiKey,
      from,
      to,
      reportId,
      email,
    );
  } catch (error) {
    // La denuncia ya está persistida: una incidencia del correo nunca debe hacer
    // creer al usuario que no se registró.
    logger.error('submitModerationReport: moderator email failed', {
      reportId,
      error,
    });
    try {
      await reportRef.update({
        emailDelivery: {
          status: 'failed',
          provider: 'resend',
          attemptedAt: Timestamp.now(),
        },
      });
    } catch (updateError) {
      logger.error('submitModerationReport: could not record email failure', {
        reportId,
        updateError,
      });
    }
    return;
  }

  try {
    await reportRef.update({
      emailDelivery: {
        status: 'sent',
        provider: 'resend',
        providerMessageId,
        attemptedAt: Timestamp.now(),
      },
    });
  } catch (error) {
    // El correo ya salió. No lo marques como fallido ni lo reenvíes solo porque
    // Firestore no pudo guardar el acuse del proveedor.
    logger.error('submitModerationReport: could not record email success', {
      reportId,
      providerMessageId,
      error,
    });
  }
}

export const submitModerationReport = onCall(
  {
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [resendApiKey],
  },
  async (request) => {
    const reporterId = request.auth?.uid;
    if (!reporterId) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }
    const payload = parseReportPayload(request.data);
    const result = await createModerationReport(db, reporterId, payload);
    if (result.created) await notifyModerator(result.reportId);
    return { created: result.created, reportId: result.reportId };
  },
);
