import { IncomingMessage, ServerResponse } from 'http';

export function healthController(
  _req: IncomingMessage,
  res: ServerResponse,
): ServerResponse {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ status: 'ok' }));
  return res;
}

export function versionController(
  _req: IncomingMessage,
  res: ServerResponse,
): ServerResponse {
  const version = process.env.APP_VERSION || '1.0.0';
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ version }));
  return res;
}
