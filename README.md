# ChemLabel Maker

A single-file browser app for generating **Avery 5163** chemical laboratory labels. Type a chemical name, auto-fetch its structure and GHS hazard data from PubChem, compose a label, assign it to a cell on a virtual label sheet, and export to PDF or print.

---

## Quick Start

```bash
# Windows
run.bat

# Any platform with Python 3
python -m http.server 8080
# then open http://localhost:8080
```

> **Must be served over HTTP.** Opening `index.html` directly as `file://` will trigger CORS blocks on the PubChem API and local GHS SVG images. The app detects this and shows a warning banner.

---

## File Structure

```
index.html          ← entire application (HTML + CSS + JS, ~1760 lines)
run.bat             ← Windows helper: starts Python server + opens browser
ghs/
  GHS01.svg         ← Explosive
  GHS02.svg         ← Flammable
  GHS03.svg         ← Oxidizing
  GHS04.svg         ← Compressed Gas
  GHS05.svg         ← Corrosive
  GHS06.svg         ← Toxic
  GHS07.svg         ← Irritant
  GHS08.svg         ← Health Hazard
  GHS09.svg         ← Environmental
```

There is no build step, no package manager, and no server-side code. Everything is in `index.html`.

---

## External Dependencies (CDN)

All loaded from unpkg/Google Fonts at runtime:

| Library | Version | Purpose |
|---|---|---|
| `smiles-drawer` | 2.1.7 | Render SMILES strings into SVG molecule diagrams |
| `html2canvas` | 1.4.1 | Rasterize the label sheet to a canvas for PDF export |
| `jsPDF` | 2.5.1 | Encode the canvas as a PDF file |
| IBM Plex Sans / Mono | — | UI fonts (Google Fonts) |

---

## Label Sheet Format

Matches **Avery 5163** (also compatible with 5263, 8163):
- Paper: 8.5" × 11" US Letter
- Grid: 2 columns × 5 rows = **10 labels per sheet**
- Label size: 4" × 2" each

The sheet preview is rendered at 816 × 1056 px (96 dpi equivalent). PDF export captures it at 3× scale and maps it to a 612 × 792 pt letter PDF.

---

## Architecture

### State

All mutable state lives in two top-level objects:

```js
// Sheet state
const state = {
  cells: Array(10).fill(null),  // null | 'used' | LabelData
  selectedCell: null            // 0–9 or null
};

// Per-element typography settings
const typo = {
  header:       { font, size, bold, italic, underline },
  manufacturer: { ... },
  subheader:    { ... },
  footer:       { ... },
};
```

A cell value of `'used'` means the cell is marked unavailable (shown with a strikethrough in the mini-grid). A cell value of `null` means empty. Otherwise it holds a `LabelData` object (see below).

### LabelData Object

This is what gets stored in `state.cells[i]` when a label is placed:

```js
{
  name: string,                 // header / label name
  manufacturer: string,         // optional source/manufacturer
  manufacturerPrefix: string,   // e.g. "Manufacturer:"
  manufacturerShowPrefix: bool,
  chemicals: [
    {
      name: string,             // display name (not used in rendering)
      smiles: string,           // SMILES string for structure drawing
      formula: string,          // molecular formula (displayed as subheader hint)
      ghs: string[],            // e.g. ['GHS02', 'GHS06']
    }
  ],
  footer: [
    {
      key: string,              // field label, e.g. "Lot"
      value: string,            // filled value, or empty = write-in blank
      showPrefix: bool,         // whether to print "Lot: " prefix
    }
  ],
  footerLine: bool,             // show separator line above footer
}
```

### Key Functions

| Function | Description |
|---|---|
| `init()` | Entry point. Builds UI, grid, adds default chemical component and footer presets. |
| `buildMiniGrid()` | Renders the 10-cell mini-grid in the left panel (click to select, right-click to toggle used). |
| `buildLabelGrid()` | Renders the full-size sheet preview on the right. Calls `buildLabelDOM()` per filled cell. |
| `buildLabelDOM(labelData, i)` | Constructs the DOM tree for a single label. Calls SmilesDrawer, assembles GHS images, applies typography. |
| `collectLabel()` | Reads all form inputs and returns a `LabelData` object. |
| `addLabelToSheet()` | Calls `collectLabel()`, stores result in `state.cells[selectedCell]`, rebuilds both grids. |
| `lookupChem(id)` | Fetches CID, SMILES, formula from PubChem by name. Then calls `fetchGHS()`. |
| `fetchGHS(id, cid)` | Fetches GHS classification from PubChem `pug_view` endpoint. Parses `GHS0X` codes from JSON. |
| `downloadPDF()` | Hides UI, captures `.sheet-preview` via html2canvas at 3× scale, saves as PDF via jsPDF. |
| `normalizeSvgStructure(svgEl)` | Crops a SmilesDrawer-rendered SVG to its tight content bounding box. See note below. |
| `applyTypo(el, key)` | Applies `typo[key]` font settings to a DOM element's inline style. |

---

## PubChem API Integration

Two endpoints are used:

1. **CID lookup** — resolve a chemical name to a PubChem Compound ID:
   ```
   GET /rest/pug/compound/name/{name}/cids/JSON
   ```

2. **Properties** — fetch SMILES and molecular formula by CID:
   ```
   GET /rest/pug/compound/cid/{cid}/property/SMILES,IsomericSMILES,CanonicalSMILES,MolecularFormula/JSON
   ```

3. **GHS classification** — fetch hazard pictogram data:
   ```
   GET /rest/pug_view/data/compound/{cid}/JSON?heading=GHS+Classification
   ```
   GHS codes (`GHS01`–`GHS09`) are extracted from the response by regex-scanning the full JSON string, then confirmed via the `Markup[].Extra` and `Markup[].URL` fields.

All three calls first try `fetch()`, then fall back to **JSONP** (`fetchJSONP()`) if fetch fails due to CORS. The JSONP fallback injects a `<script>` tag and expects PubChem to call the generated callback.

Lookup is debounced 800 ms from the last keystroke (`scheduleChemLookup()`). Users can also click the 🔍 button to trigger immediately, or paste a SMILES string directly to bypass the API entirely.

---

## SMILES Structure Rendering

SmilesDrawer is used in **synchronous SVG mode** (`SmilesDrawer.SvgDrawer`):

```js
const drawer = new SmilesDrawer.SvgDrawer({ width, height, ...options });
SmilesDrawer.parse(smiles, (tree) => {
  drawer.draw(tree, svgElement, 'light', null, false);
}, errorCallback);
```

### SVG Normalization (`normalizeSvgStructure`)

SmilesDrawer wraps its output in a centering `<g transform="translate(cx,cy)">`. Scanning child elements' `getBBox()` directly returns coordinates in local space (near-zero), not the SVG root coordinate space — this produces a large empty gap above the molecule.

The fix: temporarily move all drawable children into an unpositioned probe `<g>`, call `probe.getBBox()` (which accumulates transforms), then restore the children. This gives the true bounding box in SVG-root coordinates.

After normalizing, each chemical's bounding box is collected into `normList`. A layout algorithm then tries every column count from 1 to N and picks the one that maximises `min(availW/layoutW, availH/layoutH)` — i.e. the arrangement where structures appear largest in the available space. Structures are then placed into the combined SVG according to that grid.

**Sentinel rect.** Each structure's `<g>` in the combined SVG contains an invisible `<rect>` (same dimensions as the normalized bounding box, `fill="none" stroke="none"`). Browsers lazily defer layout computation for off-screen/hidden SVG subtrees, and `getBBox()` — which is supposed to force a synchronous reflow — does not always honour this guarantee for deeply nested `<g transform="...">` trees. Having a concrete geometry element (`<rect>` with explicit `width`/`height`) already present in the live DOM from a prior render appears to warm up the browser's SVG layout engine, making subsequent `getBBox()` calls on the hidden `tmpSvg` reliable. Removing the sentinel causes `getBBox()` to return stale dimensions, breaking the layout decision. The root cause is a browser quirk, not a logic error.

---

## GHS Pictogram Display

GHS SVGs are loaded from the local `./ghs/` directory as `<img>` elements. If an image fails to load (e.g., wrong path, missing file), an inline fallback `<div>` renders the GHS code as red text.

Symbol size is adaptive:
- 1–2 symbols → 48 px
- 3 symbols → 36 px
- 4+ symbols → 28 px

---

## Typography System

Four label elements have independently configurable typography: **Header**, **Manufacturer**, **Subheader labels**, and **Footer fields**.

Clicking **Aa ▾** in the panel reveals the typography panel. Settings are stored in the `typo` object and applied via `applyTypo(domEl, key)` each time a label is rendered. Changes only take effect when a label is (re-)placed on the sheet.

Font size is stored in `pt` and written to CSS as `px` at a 1:1 ratio (targeting 96 dpi screen rendering).

---

## PDF Export

1. `header`, `.panel`, and `.preview-header` are hidden with `visibility: hidden` (not `display:none`, to preserve layout).
2. `.pdf-capture` class is added to `.sheet-preview`, which removes dashed cell borders via a CSS rule.
3. `html2canvas` captures `.sheet-preview` at `scale: 3` (high resolution) with `useCORS: true` (required for the local `ghs/*.svg` files served over HTTP).
4. The canvas is encoded as JPEG at 0.95 quality and placed into a jsPDF `letter`-format document.
5. `visibility` is restored in a `finally` block regardless of success or failure.

---

## Footer Fields

Footer fields are drag-reorderable rows. Each row has:
- A drag handle (only dragging from the handle initiates the drag, preventing accidental reorders while typing)
- A **key** input (field name/label)
- A **value** input (filled value, or left empty to render a write-in underline on the printed label)
- A **pfx** checkbox (whether to print `"Key: "` before the value)
- A remove button

Preset buttons (Lot, Lab, EXP, etc.) are tracked in `activePresets` (a `Set`) to prevent duplicates. The "Lab" preset defaults with prefix hidden since lab codes are typically written without a label.

---

## Development Notes

- The app has **no build step**. Edit `index.html` and refresh the browser.
- All CSS uses custom properties defined in `:root`. Colors, fonts, and the label dimensions (`--label-w`, `--label-h`) are centrally controlled.
- `updatePreview()` is currently a no-op — the label preview only updates when the user clicks **Place Label on Sheet**. This is intentional to avoid expensive re-renders on every keystroke.
- If you need to add a new label field, add it to `collectLabel()`, `buildLabelDOM()`, and `clearLabel()`.
- If you add more GHS symbols beyond GHS09, add the SVG to `ghs/` and register the code in the `GHS_SYMBOLS` object.
