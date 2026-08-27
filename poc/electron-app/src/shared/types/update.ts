export type UpdateStateName =
  | 'CHECKING' | 'LATEST' | 'UPDATE_AVAILABLE'
  | 'READY_OPTIONAL' | 'READY_FORCE' | 'RESTARTING' | 'ERROR';

export type UpdateMode = 'optional' | 'force';

export interface UpdatePolicy {
  product: string;
  channel: string;
  latestVersion: string;
  minimumSupportedVersion: string;
  mode: UpdateMode;
  releaseNotes: string[];
}

export interface UpdateState {
  state: UpdateStateName;
  runningVersion: string;
  installedVersion: string;
  latestVersion: string;
  mode: UpdateMode | null;
  releaseNotes: string[];
  stateSource: 'update-state.json' | 'fallback';
  error?: string;
  upgradedFrom?: string; // spec §11: set by main when getVersion() > lastSeenVersion (first run after upgrade)
}
