import { render } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { Markdown } from "./Markdown";

/** NIC-129 Increment 4: the minimal in-house markdown renderer for PROJECT.md descriptors —
 *  headings, unordered lists, paragraphs, and inline bold/italic, with no raw-HTML passthrough. */

describe("Markdown (NIC-129 minimal renderer)", () => {
  it("renders ATX headings at their level", () => {
    const { container } = render(<Markdown source={"# Title\n## Subtitle"} />);
    expect(container.querySelector("h1")?.textContent).toBe("Title");
    expect(container.querySelector("h2")?.textContent).toBe("Subtitle");
  });

  it("renders inline bold and italic", () => {
    const { container } = render(<Markdown source={"This is **bold** and _italic_ text."} />);
    expect(container.querySelector("strong")?.textContent).toBe("bold");
    expect(container.querySelector("em")?.textContent).toBe("italic");
  });

  it("renders an unordered list", () => {
    const { container } = render(<Markdown source={"- one\n- two\n- three"} />);
    const items = container.querySelectorAll("li");
    expect(items).toHaveLength(3);
    expect(items[0].textContent).toBe("one");
  });

  it("renders paragraphs, joining soft-wrapped lines and splitting on blank lines", () => {
    const { container } = render(<Markdown source={"first line\nsecond line\n\nnext para"} />);
    const paras = container.querySelectorAll("p");
    expect(paras).toHaveLength(2);
    expect(paras[0].textContent).toBe("first line second line");
    expect(paras[1].textContent).toBe("next para");
  });

  it("escapes raw HTML to literal text — no markup or script injection", () => {
    const { container } = render(<Markdown source={"<script>alert(1)</script> **safe**"} />);
    expect(container.querySelector("script")).toBeNull();
    expect(container.textContent).toContain("<script>alert(1)</script>");
    expect(container.querySelector("strong")?.textContent).toBe("safe");
  });

  it("leaves unsupported syntax as literal text rather than mis-rendering it", () => {
    const { container } = render(<Markdown source={"see [a link](https://example.com)"} />);
    // Links are outside the supported subset, so they stay as plain text (no anchor element).
    expect(container.querySelector("a")).toBeNull();
    expect(container.textContent).toContain("[a link](https://example.com)");
  });
});
