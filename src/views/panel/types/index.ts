export interface AwakeStatus {
  readonly enabled: boolean;
  readonly expiresAt: number | null;
  readonly durationSeconds: number | null;
  readonly error: string | null;
}
