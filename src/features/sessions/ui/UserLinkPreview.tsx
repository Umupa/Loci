import { t, useLocale } from "../../../shared/i18n/locale";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect,useState,type MouseEvent } from "react";
import { fetchLinkPreviewMetadata,type LinkPreviewMetadata,type UserLink } from "../model/linkPreview";

export function UserLinkPreview({ link }: { link: UserLink }) {
  useLocale();
  return <GenericLinkPreview link={link} />;
}

function GenericLinkPreview({ link }: { link: UserLink }) {
  useLocale();
  const [metadata, setMetadata] = useState<LinkPreviewMetadata | null>(null);
  const [faviconFailed, setFaviconFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setMetadata(null);
    setFaviconFailed(false);
    void fetchLinkPreviewMetadata(link.url)
      .then((value) => {
        if (!cancelled) setMetadata(value);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [link.url]);

  const title = metadata?.title?.trim() || link.host;
  const favicon = faviconFailed ? null : metadata?.faviconDataUrl;

  return (
    <a
      href={link.url}
      data-user-link-preview
      title={link.url}
      aria-label={t("Open {0}", title)}
      className="user-link-preview group mx-0.5 text-sky-400/90 hover:text-sky-300 hover:underline"
      onClick={(event) => openExternalLink(event, link.url)}
    >
      <span className="mr-1 inline-flex size-4 items-center justify-center overflow-hidden rounded bg-background-base/50 align-[-0.125em] text-[9px] font-semibold uppercase text-content/55">
        {favicon ? (
          <img
            src={favicon}
            alt=""
            draggable={false}
            className="size-3.5 object-contain"
            onError={() => setFaviconFailed(true)}
          />
        ) : (
          link.host.charAt(0)
        )}
      </span>
      <span className="user-link-preview-title font-medium group-hover:underline">
        {title}
      </span>
    </a>
  );
}

function openExternalLink(event: MouseEvent<HTMLAnchorElement>, url: string) {
  event.preventDefault();
  event.stopPropagation();
  void openUrl(url).catch((error) => {
    console.error("Failed to open web link:", error);
  });
}
