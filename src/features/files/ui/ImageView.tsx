import { formatFileSize } from "../../../shared/lib/filePreview";
import { ImageViewport } from "../../../shared/ui/ImageViewport";

export function ImageView({ url, size, mime, focused = true }: { url: string; size: number; mime: string; focused?: boolean }) {
  return <ImageViewport src={url} alt="" active={focused ? "focused" : undefined} metadata={<>
    <span className="mr-2 tabular-nums">{formatFileSize(size)}</span>
    <span className="uppercase">{mime.replace(/^image\//, "")}</span>
  </>} />;
}
