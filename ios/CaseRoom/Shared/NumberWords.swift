/*
 * Purpose: Shared 0–99 number-to-words helper ("Fifty-eight") for screens that
 *          spell out small counts in prose — Timeline's day-count headline and
 *          Home's drills/minutes hero both spell counts the same way.
 * Inputs: none.
 * Outputs: NumberWords.spellOut(_:).
 * Run: `NumberWords.spellOut(58) == "Fifty-eight"`.
 */

import Foundation

enum NumberWords {
    /// 0–99 spelled out, first letter capitalized ("Fifty-eight"); >=100 falls
    /// back to digits. Callers needing a mid-sentence (lowercase-leading) form
    /// should call `.lowercased()` on the result.
    static func spellOut(_ n: Int) -> String {
        guard n >= 0, n < 100 else { return "\(n)" }
        let ones = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                    "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
                    "Eighteen", "Nineteen"]
        if n < 20 { return ones[n] }
        let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
        let ten = n / 10, rem = n % 10
        return rem == 0 ? tens[ten] : "\(tens[ten])-\(ones[rem].lowercased())"
    }
}
