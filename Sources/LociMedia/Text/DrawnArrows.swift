/// Draws the arrowheads and other markers of a diagram into it as plain shapes, since the picture it becomes is
/// shown by a renderer that leaves markers out. Defines `lociDrawMarkers(svg, page)`: every `marker-start`,
/// `marker-mid` and `marker-end` becomes a copy of its marker turned and placed where the line starts, bends or
/// ends, painted in the line's stroke; the attributes and the markers themselves go.
enum DrawnArrows {
  static let script = #"""
    const lociDrawMarkers = (svg, page) => {
      const number = /[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi;
      const segmentsOf = element => {
        const point = (x, y) => [x, y];
        const line = (from, to) => ({ from, to, out: [to[0] - from[0], to[1] - from[1]], in: [to[0] - from[0], to[1] - from[1]] });
        const curve = (from, first, last, to) => {
          const direction = (a, b) => [b[0] - a[0], b[1] - a[1]];
          const still = ([dx, dy]) => dx === 0 && dy === 0;
          const out = [direction(from, first), direction(from, last), direction(from, to)].find(d => !still(d));
          const into = [direction(last, to), direction(first, to), direction(from, to)].find(d => !still(d));
          return { from, to, out: out ?? [0, 0], in: into ?? [0, 0] };
        };
        const tag = element.tagName.toLowerCase();
        const at = name => parseFloat(element.getAttribute(name)) || 0;
        if (tag === "line") return [line(point(at("x1"), at("y1")), point(at("x2"), at("y2")))];
        if (tag === "polyline" || tag === "polygon") {
          const values = (element.getAttribute("points") ?? "").match(number)?.map(Number) ?? [];
          const points = [];
          for (let index = 0; index + 1 < values.length; index += 2) points.push(point(values[index], values[index + 1]));
          if (tag === "polygon" && points.length > 2) points.push(points[0]);
          return points.slice(1).map((to, index) => line(points[index], to));
        }
        if (tag !== "path") return [];
        const segments = [];
        let current = point(0, 0), start = current, control = null;
        for (const [, letter, list] of (element.getAttribute("d") ?? "").matchAll(/([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)/g)) {
          const values = list.match(number)?.map(Number) ?? [];
          const relative = letter === letter.toLowerCase() && letter !== "z" ? 1 : 0;
          const command = letter.toUpperCase();
          const take = (count, draw) => {
            for (let index = 0; index + count <= values.length; index += count) {
              const shift = (dx, dy) => point(dx + relative * current[0], dy + relative * current[1]);
              draw(values.slice(index, index + count), shift, index);
            }
          };
          if (command === "M") {
            take(2, ([x, y], shift, index) => {
              const to = shift(x, y);
              if (index > 0) segments.push(line(current, to));
              current = to;
              if (index === 0) start = to;
            });
            control = null;
          } else if (command === "L" || command === "T") {
            take(2, ([x, y], shift) => { const to = shift(x, y); segments.push(line(current, to)); current = to; });
            control = null;
          } else if (command === "H") {
            take(1, ([x]) => { const to = point(x + relative * current[0], current[1]); segments.push(line(current, to)); current = to; });
            control = null;
          } else if (command === "V") {
            take(1, ([y]) => { const to = point(current[0], y + relative * current[1]); segments.push(line(current, to)); current = to; });
            control = null;
          } else if (command === "C") {
            take(6, ([x1, y1, x2, y2, x, y], shift) => {
              const first = shift(x1, y1), last = shift(x2, y2), to = shift(x, y);
              segments.push(curve(current, first, last, to));
              current = to;
              control = last;
            });
          } else if (command === "S") {
            take(4, ([x2, y2, x, y], shift) => {
              const first = control ? point(2 * current[0] - control[0], 2 * current[1] - control[1]) : current;
              const last = shift(x2, y2), to = shift(x, y);
              segments.push(curve(current, first, last, to));
              current = to;
              control = last;
            });
          } else if (command === "Q") {
            take(4, ([x1, y1, x, y], shift) => {
              const middle = shift(x1, y1), to = shift(x, y);
              segments.push(curve(current, middle, middle, to));
              current = to;
              control = null;
            });
          } else if (command === "A") {
            take(7, ([, , , , , x, y], shift) => { const to = shift(x, y); segments.push(line(current, to)); current = to; });
            control = null;
          } else if (command === "Z") {
            if (current[0] !== start[0] || current[1] !== start[1]) segments.push(line(current, start));
            current = start;
            control = null;
          }
        }
        return segments;
      };

      const degrees = ([dx, dy]) => (Math.atan2(dy, dx) * 180) / Math.PI;
      const markerOf = (value) => {
        const id = /#([^)"']+)/.exec(value ?? "")?.[1];
        if (!id) return null;
        return [...svg.querySelectorAll("marker")].find(marker => marker.id === id) ?? page.getElementById(id);
      };
      const place = (marker, line, [x, y], angle, reversed) => {
        const orient = marker.getAttribute("orient") ?? "0";
        const turn = orient === "auto" ? angle : orient === "auto-start-reverse" ? angle + (reversed ? 180 : 0) : parseFloat(orient) || 0;
        const view = (marker.getAttribute("viewBox") ?? "").split(/[\s,]+/).map(Number);
        const width = parseFloat(marker.getAttribute("markerWidth") ?? "3") || 3;
        const height = parseFloat(marker.getAttribute("markerHeight") ?? "3") || 3;
        const fits = view.length === 4 && view[2] > 0 && view[3] > 0 ? Math.min(width / view[2], height / view[3]) : 1;
        const units = marker.getAttribute("markerUnits") === "userSpaceOnUse" ? 1 : parseFloat(line.getAttribute("stroke-width") ?? "1") || 1;
        const refX = parseFloat(marker.getAttribute("refX") ?? "0") || 0;
        const refY = parseFloat(marker.getAttribute("refY") ?? "0") || 0;
        const group = page.createElementNS("http://www.w3.org/2000/svg", "g");
        group.setAttribute("transform", `translate(${x} ${y}) rotate(${turn}) scale(${fits * units}) translate(${-refX} ${-refY})`);
        const paint = line.closest("[stroke]")?.getAttribute("stroke");
        const paintOpacity = line.closest("[stroke-opacity]")?.getAttribute("stroke-opacity");
        for (const child of marker.childNodes) group.appendChild(child.cloneNode(true));
        for (const shape of group.querySelectorAll("*")) {
          shape.removeAttribute("id");
          if (!paint || paint === "none") continue;
          if (shape.getAttribute("fill") !== "none") {
            shape.setAttribute("fill", paint);
            if (paintOpacity) shape.setAttribute("fill-opacity", paintOpacity);
          }
          if (shape.hasAttribute("stroke") && shape.getAttribute("stroke") !== "none") shape.setAttribute("stroke", paint);
          shape.setAttribute("stroke-dasharray", "none");
        }
        line.after(group);
      };
      const ends = ["marker-start", "marker-mid", "marker-end"];
      for (const line of [...svg.querySelectorAll(ends.map(end => `[${end}]`).join(", "))]) {
        if (line.closest("marker")) continue;
        const segments = segmentsOf(line);
        if (segments.length > 0) {
          const end = markerOf(line.getAttribute("marker-end"));
          const middle = markerOf(line.getAttribute("marker-mid"));
          const begin = markerOf(line.getAttribute("marker-start"));
          if (end) { const last = segments[segments.length - 1]; place(end, line, last.to, degrees(last.in), false); }
          if (middle) {
            segments.slice(1).forEach((segment, index) => {
              const before = degrees(segments[index].in), after = degrees(segment.out);
              const bend = Math.abs(after - before) > 180 ? (before + after) / 2 + 180 : (before + after) / 2;
              place(middle, line, segment.from, bend, false);
            });
          }
          if (begin) place(begin, line, segments[0].from, degrees(segments[0].out), true);
        }
        for (const end of ends) line.removeAttribute(end);
      }
      for (const marker of [...svg.querySelectorAll("marker")]) marker.remove();
    };
    """#
}
