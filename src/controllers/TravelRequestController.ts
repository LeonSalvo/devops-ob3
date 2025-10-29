import { IncomingMessage, ServerResponse } from 'http';
import { TravelRequestService } from '../services/TravelRequestService';
import { parseBody } from '../utils/http';

const travelRequestService = TravelRequestService.getInstance();

export async function createTravelRequestController(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<ServerResponse> {
  try {
    const body = await parseBody(req);
    const { employee, destination, days } = body;

    if (!employee || !destination || !days) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ error: 'Missing required fields' }));
      return res;
    }

    const travelRequest = travelRequestService.createTravelRequest(
      employee,
      destination,
      days,
    );
    res.statusCode = 201;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(travelRequest));
    return res;
  } catch (error) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Internal server error' }));
    return res;
  }
}

export function getAllTravelRequestsController(
  _req: IncomingMessage,
  res: ServerResponse,
): ServerResponse {
  const travelRequests = travelRequestService.getAllTravelRequests();
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(travelRequests));
  return res;
}

export function approveTravelRequestController(
  req: IncomingMessage,
  res: ServerResponse,
): ServerResponse {
  // Extract ID from URL pattern /api/travel-requests/{id}/approve
  const urlParts = req.url?.split('/') || [];
  const id = urlParts[urlParts.length - 2]; // Get the ID part
  if (!id) {
    res.statusCode = 400;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Invalid request ID' }));
    return res;
  }

  const travelRequest = travelRequestService.approveTravelRequest(id);
  if (!travelRequest) {
    res.statusCode = 404;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Travel request not found' }));
    return res;
  }

  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(travelRequest));
  return res;
}
