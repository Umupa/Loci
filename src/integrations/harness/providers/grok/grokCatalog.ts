import { homeDir } from "../../../../platform/tauri/fs";
import {
  setHarnessModels,
  type AgentModel,
} from "../../../../features/sessions/model/models";
import { AcpClient } from "../../core/acp";
import {
  execChild,
  killChild,
  resolveGrokBinary,
  spawnChild,
  unwatchChild,
  watchChild,
} from "../../core/child";
import {
  catalogFromGrokModelsOutput,
  currentModelId,
  fallbackGrokModels,
  grokAuthMethodId,
  grokSpawnArgs,
  modelsFromInitialize,
  modelsFromSessionNew,
  type GrokCliCatalog,
} from "./grokProtocol";

const PROBE_ID = "loci-grok-probe";
const DISCOVERY_TIMEOUT_MS = 15_000;
const REQUEST_TIMEOUT_MS = 12_000;

const CLIENT_CAPABILITIES = {
  fs: { readTextFile: false, writeTextFile: false },
  terminal: false,
};

type AcpCatalog = {
  models: AgentModel[];
  /** Model the CLI reports as current when the probe passes no `--model`. */
  currentModelId?: string;
};

export type GrokCatalog = {
  models: AgentModel[];
  /** Native id from `grok models`' `Default model:` line, when it ran. */
  defaultModelId?: string;
};

let inflight: Promise<void> | null = null;

export function refreshGrokCatalog(): Promise<void> {
  if (inflight) return inflight;
  inflight = discoverGrokModels()
    .then((catalog) => {
      if (catalog.models.length > 0) {
        setHarnessModels("grok", catalog.models, {
          defaultId: catalog.defaultModelId,
        });
      }
    })
    .catch((error: unknown) => {
      console.debug("[loci] grok catalog", error);
    })
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

export async function discoverGrokModels(
  workingDirectory?: string,
): Promise<GrokCatalog> {
  const [fromCli, fromAcp] = await Promise.all([
    discoverViaCli(workingDirectory).catch((error: unknown) => {
      console.debug("[loci] grok CLI catalog failed", error);
      return { models: [] } as GrokCliCatalog;
    }),
    discoverViaAcp(workingDirectory).catch((error: unknown) => {
      console.debug("[loci] grok ACP catalog failed", error);
      return { models: [] } as AcpCatalog;
    }),
  ]);
  const models = mergeCatalogModels(fromCli.models, fromAcp.models);
  return {
    models: models.length > 0 ? models : fallbackGrokModels(),
    defaultModelId: fromCli.defaultModelId ?? fromAcp.currentModelId,
  };
}

/**
 * The CLI list decides which models exist; the ACP probe supplies the names,
 * context windows and reasoning options that `grok models` does not print.
 * ACP-only entries still append so a model the probe knows is not hidden.
 */
function mergeCatalogModels(
  cli: AgentModel[],
  acp: AgentModel[],
): AgentModel[] {
  if (cli.length === 0) return acp;
  const richByNative = new Map(
    acp.map((model) => [nativeKey(model), model]),
  );
  const merged = cli.map((model) => {
    const key = nativeKey(model);
    const rich = richByNative.get(key);
    if (!rich) return model;
    richByNative.delete(key);
    return { ...rich, id: model.id };
  });
  return [...merged, ...richByNative.values()];
}

function nativeKey(model: AgentModel): string {
  return model.nativeId ?? model.id.slice(model.id.indexOf(":") + 1);
}

async function discoverViaAcp(
  workingDirectory?: string,
): Promise<AcpCatalog> {
  const { path } = await resolveGrokBinary();
  const cwd = workingDirectory ?? (await homeDir());
  const probeId = `${PROBE_ID}-${crypto.randomUUID()}`;
  const acp = new AcpClient(probeId, {
    onRequest: (id) => {
      void acp.respond(id, {}).catch(() => undefined);
    },
  });

  const stop = async () => {
    acp.close();
    unwatchChild(probeId);
    await killChild(probeId).catch(() => undefined);
  };

  watchChild(
    probeId,
    (line) => acp.pushLine(line),
    () => acp.close(new Error("Grok Build probe exited")),
  );

  try {
    await spawnChild(
      probeId,
      path,
      grokSpawnArgs({ model: "" }),
      cwd,
      undefined,
      "grok",
    );
    return await withTimeout(DISCOVERY_TIMEOUT_MS, async () => {
      const init = await acp.request(
        "initialize",
        {
          protocolVersion: 1,
          clientCapabilities: CLIENT_CAPABILITIES,
          clientInfo: { name: "loci", version: "0.1.0" },
        },
        REQUEST_TIMEOUT_MS,
      );
      const fromInit = modelsFromInitialize(init);
      if (fromInit.length > 0) {
        return { models: fromInit, currentModelId: currentModelId(init) };
      }

      const methodId = grokAuthMethodId(init);
      if (methodId) {
        await acp
          .request(
            "authenticate",
            { methodId, _meta: { headless: true } },
            REQUEST_TIMEOUT_MS,
          )
          .catch(() => undefined);
      }
      const created = await acp.request(
        "session/new",
        { cwd, mcpServers: [] },
        REQUEST_TIMEOUT_MS,
      );
      return {
        models: modelsFromSessionNew(created),
        currentModelId: currentModelId(created),
      };
    }, () => {
      void stop();
    });
  } finally {
    await stop();
  }
}

async function discoverViaCli(
  workingDirectory?: string,
): Promise<GrokCliCatalog> {
  const { path } = await resolveGrokBinary();
  const cwd = workingDirectory ?? (await homeDir());
  const stdout = await execChild(path, ["models"], cwd, "grok");
  return catalogFromGrokModelsOutput(stdout);
}

function withTimeout<T>(
  ms: number,
  run: () => Promise<T>,
  onTimeout: () => void,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      onTimeout();
      reject(new Error("Grok Build catalog probe timed out"));
    }, ms);
    run()
      .then(resolve, reject)
      .finally(() => clearTimeout(timer));
  });
}
