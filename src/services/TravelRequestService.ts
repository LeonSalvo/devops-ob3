import { TravelRequest } from '../models/TravelRequest';
import { generateId } from '../utils/http';

export class TravelRequestService {
  private static instance: TravelRequestService;
  private travelRequests: TravelRequest[] = [];

  public static getInstance(): TravelRequestService {
    if (!TravelRequestService.instance) {
      TravelRequestService.instance = new TravelRequestService();
    }
    return TravelRequestService.instance;
  }

  createTravelRequest(
    employee: string,
    destination: string,
    days: number,
  ): TravelRequest {
    const travelRequest: TravelRequest = {
      id: generateId(),
      employee,
      destination,
      days,
      approved: false,
      createdAt: new Date(),
    };

    this.travelRequests.push(travelRequest);
    return travelRequest;
  }

  getAllTravelRequests(): TravelRequest[] {
    return this.travelRequests;
  }

  approveTravelRequest(id: string): TravelRequest | null {
    const travelRequest = this.travelRequests.find((tr) => tr.id === id);
    if (!travelRequest) {
      return null;
    }

    travelRequest.approved = true;
    return travelRequest;
  }
}
