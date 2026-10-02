// Shared runtime options for every trusted callable (functions/src/*.ts).
//
// Two reasons this exists:
//
//  1. REGION — the trusted backend sits next to an India-first audience. The
//     Firebase default (us-central1) adds a full round trip to every daily
//     credit, purchase and battle settlement. asia-south1 (Mumbai) removes it.
//     The Flutter client MUST call the same region — see
//     `TrustedOpsService` (`FirebaseFunctions.instanceFor(region: ...)`).
//
//  2. APP CHECK — `enforceAppCheck: true` makes the backend reject any call
//     that does not carry a valid App Check token, so a repackaged client or a
//     script using the public web API key cannot hit the economy callables
//     directly. The Flutter client activates App Check in `lib/main.dart`.
//
// It also sets cost guards (memory / timeout / maxInstances) so a runaway or
// abusive client cannot scale the backend without bound.
import { runWith } from 'firebase-functions/v1';

/** Region every callable is pinned to — keep in sync with the client. */
export const REGION = 'asia-south1';

export interface CallableOptions {
  /** Secret names to inject into process.env for this function. */
  secrets?: string[];
  timeoutSeconds?: number;
  maxInstances?: number;
  memory?: '128MB' | '256MB' | '512MB' | '1GB';
}

/** Builds a v1 callable with the shared region, App Check and cost guards. */
export function callable(options: CallableOptions = {}) {
  return runWith({
    enforceAppCheck: true,
    memory: options.memory ?? '256MB',
    timeoutSeconds: options.timeoutSeconds ?? 60,
    maxInstances: options.maxInstances ?? 20,
    ...(options.secrets ? { secrets: options.secrets } : {}),
  }).region(REGION);
}
