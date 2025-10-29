export interface TravelRequest {
  id: string;
  employee: string;
  destination: string;
  days: number;
  approved: boolean;
  createdAt: Date;
}
