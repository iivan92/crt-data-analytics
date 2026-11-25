// Simple FXR-style prototype (Node.js) of get_crt_info logic from crt_liquidez_tv.pine
// Run with: node crt_liquidez_fxr.js

const tp_sweep_pct = 0.5;
const tp_run_ext = 1.618;

// Compute CRT info for one timeframe using a single-bar context (values from Pine: h2,l2,h1,l1,c1,h0,l0,c0)
function getCrtInfo({ h2, l2, h1, l1, c1, h0, l0, c0 }) {
  let c_bias = "-";
  let pot = "-";
  let t1 = NaN;
  let t2 = NaN;
  let label_t1 = "";
  let label_t2 = "";

  const range_prev = h2 - l2;
  const mid = l2 + range_prev * tp_sweep_pct;
  const ext_bull = l2 + range_prev * tp_run_ext;
  const ext_bear = h2 - range_prev * tp_run_ext;

  // 1. Confirmed bias
  if (l1 < l2 && c1 > l2 && h1 < h2) {
    // BULL SWEEP
    if (h0 < mid && l0 >= l1) {
      c_bias = "B.SWP";
      t1 = mid;
      t2 = h2;
      label_t1 = "50% B.SWP";
      label_t2 = "100% B.SWP";
    }
  } else if (h1 > h2 && c1 > h2 && l1 > l2) {
    // BULL RUN
    if (h0 < ext_bull && l0 >= l2) {
      c_bias = "B.RUN";
      t1 = h1;
      t2 = ext_bull;
      label_t1 = "Max.Ant B.RUN";
      label_t2 = "161% B.RUN";
    }
  } else if (h1 > h2 && c1 < h2 && l1 > l2) {
    // BEAR SWEEP
    if (l0 > mid && h0 <= h1) {
      c_bias = "S.SWP";
      t1 = mid;
      t2 = l2;
      label_t1 = "50% S.SWP";
      label_t2 = "100% S.SWP";
    }
  } else if (l1 < l2 && c1 < l2 && h1 < h2) {
    // BEAR RUN
    if (l0 > ext_bear && h0 <= h2) {
      c_bias = "S.RUN";
      t1 = l1;
      t2 = ext_bear;
      label_t1 = "Min.Ant S.RUN";
      label_t2 = "161% S.RUN";
    }
  }

  // 2. Potential (current forming candle)
  if (l0 < l1 && c0 > l1) {
    pot = "B.SWP";
  } else if (h0 > h1 && c0 < h1) {
    pot = "S.SWP";
  } else if (h0 > h1 && c0 > h1) {
    pot = "B.RUN";
  } else if (l0 < l1 && c0 < l1) {
    pot = "S.RUN";
  }

  return { c_bias, pot, t1, t2, label_t1, label_t2 };
}

// Compute direction helper
function getDir(biasStr) {
  if (!biasStr || biasStr === "-") return "NEUTRO";
  if (biasStr.includes("B.SWP") || biasStr.includes("B.RUN")) return "BULL";
  if (biasStr.includes("S.SWP") || biasStr.includes("S.RUN")) return "BEAR";
  return "NEUTRO";
}

// Example runner: process a set of TFs with synthetic sample bars
function runExample() {
  // Sample data structure: for each TF provide object with h2,l2,h1,l1,c1,h0,l0,c0
  const sample = {
    MN1: {
      h2: 1.12,
      l2: 1.08,
      h1: 1.1,
      l1: 1.09,
      c1: 1.095,
      h0: 1.11,
      l0: 1.093,
      c0: 1.105,
    },
    W1: {
      h2: 1.15,
      l2: 1.05,
      h1: 1.12,
      l1: 1.07,
      c1: 1.11,
      h0: 1.13,
      l0: 1.08,
      c0: 1.12,
    },
    D1: {
      h2: 1.13,
      l2: 1.06,
      h1: 1.11,
      l1: 1.07,
      c1: 1.08,
      h0: 1.09,
      l0: 1.075,
      c0: 1.085,
    },
    H12: {
      h2: 1.125,
      l2: 1.065,
      h1: 1.115,
      l1: 1.07,
      c1: 1.075,
      h0: 1.08,
      l0: 1.07,
      c0: 1.077,
    },
    H8: {
      h2: 1.12,
      l2: 1.07,
      h1: 1.115,
      l1: 1.08,
      c1: 1.09,
      h0: 1.095,
      l0: 1.085,
      c0: 1.09,
    },
    H4: {
      h2: 1.118,
      l2: 1.072,
      h1: 1.112,
      l1: 1.08,
      c1: 1.082,
      h0: 1.088,
      l0: 1.081,
      c0: 1.086,
    },
  };

  const TFs = ["MN1", "W1", "D1", "H12", "H8", "H4"];
  const results = {};

  for (const tf of TFs) {
    results[tf] = getCrtInfo(sample[tf]);
  }

  // Compute base WRs (in FXR you'd query a DB or embed numbers)
  const baseWR = {
    MN1: 58.8,
    W1: 60.8,
    D1: 59.0,
    H12: 59.8,
    H8: 58.3,
    H4: 57.7,
  };

  // Simple synergy check (compare D1, W1, MN1 directions vs each tf)
  const dir_mn1 = getDir(results.MN1.c_bias);
  const dir_w1 = getDir(results.W1.c_bias);
  const dir_d1 = getDir(results.D1.c_bias);

  console.log("TF | CONF | POT | BASE WR | SYN");
  for (const tf of TFs) {
    const r = results[tf];
    const base = baseWR[tf] || "-";
    let syn = "-";
    if (["H12", "H8", "H4"].includes(tf)) {
      const cur = getDir(r.c_bias);
      if (cur !== "NEUTRO") {
        let align = 0,
          opp = 0;
        if (dir_d1 === cur) align++;
        else if (dir_d1 !== "NEUTRO") opp++;
        if (dir_w1 === cur) align++;
        else if (dir_w1 !== "NEUTRO") opp++;
        if (dir_mn1 === cur) align++;
        else if (dir_mn1 !== "NEUTRO") opp++;
        if (align === 3) syn = "+++ +3";
        else if (align === 2) syn = "++ +2";
        else if (align === 1 && opp === 0) syn = "+1";
        else if (opp >= 2) syn = "CONTRA";
        else if (opp === 1) syn = "MIXTO";
      }
    }
    console.log(`${tf} | ${r.c_bias} | ${r.pot} | ${base}% | ${syn}`);
  }
}

if (require.main === module) runExample();

module.exports = { getCrtInfo, getDir };
