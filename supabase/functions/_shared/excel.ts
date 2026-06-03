// =============================================================
// _shared/excel.ts
// Build .xlsx with embedded images stacked vertically
// Worksheet: "Documents" — no OCR, no data extraction
//
// Rotation: pre-rotates image bytes with imagescript (CW)
// before embedding, so Excel shows correct orientation.
//
// Uses:
//   fflate (esm.sh)          — ZIP assembly
//   imagescript (deno.land)  — CW rotation pre-processing
// =============================================================

import { zipSync } from 'https://esm.sh/fflate@0.8.2';
import { Image } from 'https://deno.land/x/imagescript@1.2.15/mod.ts';

// ─── Layout ─────────────────────────────────────────────────
// ใช้ oneCellAnchor + explicit extent (cx,cy) ที่คำนวณจากขนาดรูปจริง
// → รักษาสัดส่วนภาพ ไม่บีบยืด และคุมความกว้างได้แน่นอน
const EMU_PER_PX      = 9525;  // 1 px = 9525 EMU (96 DPI)
const TARGET_WIDTH_PX = 550;   // ความกว้างรูปใน Excel (≤ 650)
const PX_PER_ROW      = 20;    // default row height 15pt ≈ 20px @96dpi
const GAP_ROWS        = 3;     // แถวเว้นว่างระหว่างรูป
const FALLBACK_RATIO  = 1.414; // ถ้า decode dims ไม่ได้ → สมมติ A4 แนวตั้ง (h/w)

// ─── Public types ────────────────────────────────────────────
export interface XlsxImageInput {
  bytes:       Uint8Array;
  contentType: string;
  rotationCW:  number;  // 0 | 90 | 180 | 270 (clockwise degrees)
}

// ─── Main export ─────────────────────────────────────────────
/**
 * Build an .xlsx file with images stacked vertically in sheet "Documents".
 * Pre-rotates each image by rotationCW before embedding.
 * Returns raw .xlsx bytes (ZIP).
 */
export async function buildXlsxFromImages(images: XlsxImageInput[]): Promise<Uint8Array> {
  const enc = new TextEncoder();

  // ── 1. Pre-rotate + วัดขนาด + คำนวณตำแหน่ง ────────────────
  // คงลำดับรูปเดิม / คง manual rotation เดิม (rotationCW)
  interface Media {
    filename: string; data: Uint8Array; ext: 'jpg' | 'png';
    cx: number; cy: number; fromRow: number;  // EMU + row position
  }
  const media: Media[] = [];
  let cursorRow = 0;  // แถวเริ่มของรูปถัดไป (stack จากบนลงล่าง)

  for (let i = 0; i < images.length; i++) {
    const src  = images[i];
    const isPng = src.contentType.includes('png');
    const ext: 'jpg' | 'png' = isPng ? 'png' : 'jpg';
    let data = src.bytes;
    let w = 0, h = 0;  // ขนาดจริงหลังหมุน (px)

    try {
      const img = await Image.decode(data);
      if (src.rotationCW !== 0) {
        img.rotate(src.rotationCW);           // imagescript uses CW degrees
        data = isPng ? await img.encodePNG() : await img.encodeJPEG(85);
      }
      w = img.width; h = img.height;          // dims หลังหมุนแล้ว
    } catch (e) {
      console.warn(
        `[excel] image ${i + 1} decode/rotate failed, using original + fallback size:`,
        e instanceof Error ? e.message : String(e),
      );
    }

    // ขนาดที่จะแสดง: กว้างคงที่ ~550px, สูงตามสัดส่วนจริง (ไม่บีบยืด)
    const dispW = TARGET_WIDTH_PX;
    const dispH = (w > 0 && h > 0)
      ? Math.round(TARGET_WIDTH_PX * h / w)
      : Math.round(TARGET_WIDTH_PX * FALLBACK_RATIO);

    const cx = dispW * EMU_PER_PX;
    const cy = dispH * EMU_PER_PX;
    const fromRow = cursorRow;
    const rowsForImage = Math.ceil(dispH / PX_PER_ROW);
    cursorRow = fromRow + rowsForImage + GAP_ROWS;

    media.push({ filename: `image${i + 1}.${ext}`, data, ext, cx, cy, fromRow });
  }

  // ── 2. XML strings ────────────────────────────────────────
  const usedExts = [...new Set(media.map(m => m.ext))];
  const extEntries = usedExts
    .map(e => `<Default Extension="${e}" ContentType="${e === 'jpg' ? 'image/jpeg' : 'image/png'}"/>`)
    .join('\n  ');

  const ctXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  ${extEntries}
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`;

  const rootRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`;

  const wbXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="14400" windowHeight="8100"/></bookViews>
  <sheets><sheet name="Documents" sheetId="1" r:id="rId1"/></sheets>
</workbook>`;

  const wbRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`;

  const sheetXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheetViews><sheetView tabSelected="1" workbookViewId="0"><selection activeCell="A1" sqref="A1"/></sheetView></sheetViews>
  <sheetFormatPr defaultRowHeight="15" defaultColWidth="12"/>
  <sheetData/>
  <drawing r:id="rId1"/>
</worksheet>`;

  const sheetRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
</Relationships>`;

  // drawing: one oneCellAnchor per image — ขนาดจาก explicit extent (รักษาสัดส่วน)
  const anchors = media.map((m, idx) => {
    return `  <xdr:oneCellAnchor>
    <xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${m.fromRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
    <xdr:ext cx="${m.cx}" cy="${m.cy}"/>
    <xdr:pic>
      <xdr:nvPicPr>
        <xdr:cNvPr id="${idx + 2}" name="Image ${idx + 1}"/>
        <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>
      </xdr:nvPicPr>
      <xdr:blipFill>
        <a:blip r:embed="rId${idx + 1}"/>
        <a:stretch><a:fillRect/></a:stretch>
      </xdr:blipFill>
      <xdr:spPr>
        <a:xfrm><a:off x="0" y="0"/><a:ext cx="${m.cx}" cy="${m.cy}"/></a:xfrm>
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
      </xdr:spPr>
    </xdr:pic>
    <xdr:clientData/>
  </xdr:oneCellAnchor>`;
  }).join('\n');

  const drawingXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
${anchors}
</xdr:wsDr>`;

  const drawingRelsXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${media.map((m, idx) =>
  `  <Relationship Id="rId${idx + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/${m.filename}"/>`
).join('\n')}
</Relationships>`;

  const stylesXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>`;

  // ── 3. ZIP assembly ──────────────────────────────────────
  // deno-lint-ignore no-explicit-any
  const zipInput: Record<string, any> = {
    '[Content_Types].xml':                    enc.encode(ctXml),
    '_rels/.rels':                             enc.encode(rootRelsXml),
    'xl/workbook.xml':                         enc.encode(wbXml),
    'xl/_rels/workbook.xml.rels':              enc.encode(wbRelsXml),
    'xl/worksheets/sheet1.xml':               enc.encode(sheetXml),
    'xl/worksheets/_rels/sheet1.xml.rels':    enc.encode(sheetRelsXml),
    'xl/drawings/drawing1.xml':               enc.encode(drawingXml),
    'xl/drawings/_rels/drawing1.xml.rels':    enc.encode(drawingRelsXml),
    'xl/styles.xml':                           enc.encode(stylesXml),
  };
  for (const m of media) {
    // level:0 = STORE (no compression) — images are already compressed
    zipInput[`xl/media/${m.filename}`] = [m.data, { level: 0 }];
  }

  return zipSync(zipInput) as Uint8Array;
}
