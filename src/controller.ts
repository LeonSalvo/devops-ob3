import { IncomingMessage, ServerResponse } from 'http';
import {
  healthController,
  versionController,
} from './controllers/SystemController';
import {
  createTravelRequestController,
  getAllTravelRequestsController,
  approveTravelRequestController,
} from './controllers/TravelRequestController';

export function controller(
  req: IncomingMessage,
  res: ServerResponse,
): ServerResponse {
  try {
    if (
      (!req.url || req.url === '/') &&
      (!req.method || req.method === 'GET')
    ) {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/plain');
      res.end('Hello World');
      return res;
    }

    if (req.method === 'GET' && req.url === '/health') {
      return healthController(req, res);
    }

    if (req.method === 'GET' && req.url === '/') {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/plain');
      res.end('Hello World');
      return res;
    }
    if (req.method === 'GET' && req.url === '/api/version') {
      return versionController(req, res);
    }

    if (req.method === 'POST' && req.url === '/api/travel-requests') {
      void createTravelRequestController(req, res);
      return res;
    }

    if (req.method === 'GET' && req.url === '/api/travel-requests') {
      return getAllTravelRequestsController(req, res);
    }

    if (
      req.method === 'PATCH' &&
      req.url?.startsWith('/api/travel-requests/')
    ) {
      return approveTravelRequestController(req, res);
    }

    res.statusCode = 404;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Not found' }));
    return res;
  } catch (error) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Internal server error' }));
    return res;
  }
}
