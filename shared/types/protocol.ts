export type Side = 'LONG' | 'SHORT';

export interface EpochView {
  id: number;
  startTime: number;
  endTime: number;
  settlementPrice: number;
  realizedVolatility: number;
  settled: boolean;
}

export interface PositionView {
  id: number;
  side: Side;
  amount: number;
  epochId: number;
  status: 'OPEN' | 'CLOSED' | 'CLAIMED';
  pnl: number;
}
