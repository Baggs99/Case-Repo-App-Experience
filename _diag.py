"""Verify the prominence search for Fast Food Co. with the stripped fragment."""
import fitz, sys, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

doc = fitz.open("Yale/Columbia 2017.pdf")

TITLE_PROMINENT_CHARS = 150
SLIDE = 3

for case_title, expected_start in [("Fast Food Co.", 70), ("Frozen Food Co.", 75)]:
    fragment = re.sub(r"\s+", " ", case_title[:20]).lower().strip().rstrip(".,;:!?")
    print(f"\n=== {case_title}  fragment='{fragment}'  b.page_start={expected_start} ===")

    start_text = doc[expected_start].get_text("text")
    pos_on_start = start_text.lower().find(fragment)
    is_prominent = 0 <= pos_on_start < TITLE_PROMINENT_CHARS
    print(f"  pos on fitz {expected_start}: {pos_on_start}  prominent={is_prominent}")

    if not is_prominent:
        best_page = None
        best_pos = pos_on_start if pos_on_start >= 0 else float("inf")
        lo = max(0, expected_start - SLIDE)
        hi = min(len(doc), expected_start + SLIDE + 1)
        for candidate in range(lo, hi):
            if candidate == expected_start:
                continue
            ctext = doc[candidate].get_text("text")
            cpos = ctext.lower().find(fragment)
            if 0 <= cpos < best_pos:
                best_pos = cpos
                best_page = candidate
            print(f"    fitz {candidate} (p{candidate+1}): pos={cpos}")
        if best_page is not None and best_pos < TITLE_PROMINENT_CHARS:
            print(f"  => CORRECTED page_start: {expected_start} -> {best_page} (human p{best_page+1}, pos={best_pos})")
        else:
            print(f"  => No correction (best_pos={best_pos}, best_page={best_page})")

doc.close()
