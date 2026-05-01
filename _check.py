import csv, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

with open("output/case_catalog.csv", encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

h02 = [r for r in rows if "Harvard 2002" in r.get("source_pdf", "")]
print(f"Harvard 2002 cases: {len(h02)}\n")
print(f"{'#':>2}  {'pdf pages':>10}  {'printed pages':>14}  title")
print("-" * 75)
OFFSET = 4
for i, r in enumerate(h02, 1):
    ps = int(r["page_start"])
    pe = int(r["page_end"])
    printed_s = ps - OFFSET
    printed_e = pe - OFFSET
    print(f"{i:>2}  p{ps:>3}–{pe:>3}     (printed {printed_s:>3}–{printed_e:>3})   {r['case_title']}")

print()
print(f"  cases:               {len(h02)}")
print(f"  zero review:         {not any(r['needs_manual_review']=='True' for r in h02)}")
print(f"  all conf 1.0:        {all(r['extraction_confidence']=='1.0' for r in h02)}")
print(f"  Case 1 starts pdf38: {int(h02[0]['page_start']) == 38}")
print(f"  Case 2 starts pdf40: {int(h02[1]['page_start']) == 40}")
print(f"  none before pdf 38:  {all(int(r['page_start']) >= 38 for r in h02)}")
