import { HARNESSES, type HarnessId } from "../../features/sessions/model/session";
import { defaultModelId, hasLiveCatalog, modelsFor, setHarnessModels, type AgentModel } from "../../features/sessions/model/models";
import { isHarnessAvailable, probeHarnessAvailability } from "../../integrations/harness/core/availability";
import {
  emitHarnessAvailability, markHarnessAvailabilityProbed, setHarnessAvailability, type HarnessAvailability,
} from "../../integrations/harness/core/availabilityState";
import { refreshHarnessCatalogs } from "../../integrations/harness/core/registry";

/** Which agent CLIs the host has, and the models each one reported. */
export type HostModels = {
  available: HarnessAvailability;
  /** Only providers whose CLI has listed its models; the others keep the built-in lists. */
  catalogs: Partial<Record<HarnessId, { models: AgentModel[]; defaultId: string }>>;
};

/** As long as a terminal's `models list` waits: past it, the lists known so far. */
const CATALOG_WAIT_MS = 5_000;

/** On the host: probes its CLIs and reads their catalogs, then reports both. */
export async function readHostModels(harnesses: readonly HarnessId[] = HARNESSES): Promise<HostModels> {
  await probeHarnessAvailability();
  await refreshHarnessCatalogs(harnesses, { timeoutMs: CATALOG_WAIT_MS });
  const available = Object.fromEntries(HARNESSES.map((id) => [id, isHarnessAvailable(id)])) as HarnessAvailability;
  const catalogs: HostModels["catalogs"] = {};
  for (const id of HARNESSES) if (hasLiveCatalog(id)) catalogs[id] = { models: modelsFor(id), defaultId: defaultModelId(id) };
  return { available, catalogs };
}

/** In a connected window: the host's providers and models become the ones this window's pickers show. */
export function applyHostModels({ available, catalogs }: HostModels): void {
  for (const [id, catalog] of Object.entries(catalogs) as [HarnessId, NonNullable<HostModels["catalogs"][HarnessId]>][]) {
    setHarnessModels(id, catalog.models, { defaultId: catalog.defaultId });
  }
  setHarnessAvailability(available);
  markHarnessAvailabilityProbed();
  emitHarnessAvailability();
}
