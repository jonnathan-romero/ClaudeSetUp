---
name: equity-quant-researcher
description: >
  Equity quantitative research methodology, factor modeling, portfolio optimization,
  risk management, and statistical rigor for hedge fund quant research. ALWAYS trigger
  when: code involves alpha signals, backtesting, portfolio optimization, risk models,
  factor models, covariance estimation, Sharpe ratio, information coefficient, IC analysis,
  walk-forward validation, look-ahead bias, signal decay, turnover, equity quant, hedge fund,
  long-short, dollar-neutral, CVaR, drawdown, rebalance, factor exposure, cross-sectional,
  panel data, momentum, value factor, quality factor, short interest, Fama-French, Barra,
  backtest, signal evaluation, transaction costs, market impact, or quant finance.
---

# Equity Quant Research: Practitioner Methodology

You are assisting a full-stack equity quant (research through portfolio construction and risk management). Apply the following domain knowledge, thresholds, and anti-patterns in all quant work.

## 1. Research Workflow

Follow this sequence for new signal/strategy work. Each step has a gate before proceeding.

1. **Hypothesis**: State the economic mechanism BEFORE writing code. Why should this predict returns? What behavioral bias, structural friction, or risk premium does it exploit? Write rejection criteria (IC threshold, t-stat minimum) before looking at data.

2. **Data**: Fetch and validate. Check point-in-time (PIT) correctness -- every data row must reflect what was available to a real trader at that date. Enforce reporting lags: earnings 45-60 days after quarter-end, Form 4 within 2 business days, FINRA short interest ~14 day lag. Include delisted securities with realistic delisting returns (-30% proxy per Shumway when unavailable). Use total return series (dividends reinvested) for performance; price return for technical signals.

3. **Signal construction pipeline**:
   - Raw data -> compute metric -> winsorize (1st/99th percentile) -> cross-sectional transform (rank or z-score, computed per-period not full-sample) -> neutralize (sector demean, regress out log market cap) -> lag (shift(1) minimum for prices, 60+ days for quarterly fundamentals) -> final signal
   - All signals should be scored so high = better (flip signs as needed)
   - Use MAD-based z-scoring (median / 1.4826*MAD) for robustness to outliers

4. **Signal evaluation** -- GATE: must pass before backtesting:

   | Metric | Minimum | Good | Excellent |
   |--------|---------|------|-----------|
   | IC Mean (Spearman) | >0.02 | >0.04 | >0.06 |
   | IC t-stat | >2.0 | >3.0 | >5.0 |
   | ICIR (mean/std) | >0.3 | >0.5 | >1.0 |
   | Q5-Q1 spread (ann.) | >0 | >3% | >6% |
   | Monthly turnover | <50% | <30% | <15% |

   Also check: IC decay across horizons (1d, 5d, 21d, 63d), sector/size bias, correlation with known factors (momentum, value, quality). If correlated >0.5 with a known factor, evaluate incremental IC only.

5. **Backtest**: Use OpenFill or next-day-open (NEVER same-day close for signal-based strategies). Always include transaction costs (minimum 5-10bps round-trip large-cap, 20-50bps mid-cap, 50-150bps small-cap). Include short borrow costs (50-100bps/yr GC, 200-500bps/yr small-cap). Minimum 3-year out-of-sample period covering at least one significant drawdown. OOS Sharpe degradation >40% vs IS suggests overfitting.

6. **Risk analysis**: Factor decompose returns (market, size, value, momentum, quality, low-vol). Stress test against GFC 2008 (-57% SPX), COVID March 2020 (-34%), rate shock 2022 (-25%). Check concentration (HHI, effective N positions). Single position >15% of risk contribution triggers review.

7. **Capacity**: Estimate via Capacity = Participation_Rate x DDTV x 252 / Annual_Turnover. Target participation <10% of ADV. Strategy should operate below 30% of estimated capacity.

## 2. Anti-Patterns (ALWAYS prevent these)

- **NEVER** backtest without transaction costs. Cost drag = Annual_Turnover x Round_Trip_Cost. At 200% turnover and 10bps RT: 20bps/yr drag.
- **NEVER** use same-day close fills for signals computed from close prices (look-ahead bias, inflates returns 10-30bps/trade).
- **NEVER** use random train/test splits on time series. Use walk-forward or purged k-fold with embargo.
- **NEVER** optimize parameters on full sample then backtest on same data. Walk-forward only.
- **NEVER** compute IC with same-day returns. Must be forward returns (1d, 5d, 21d).
- **NEVER** annualize quarterly fundamentals with x4. Use trailing twelve months (TTM) or accept None when <4 quarters available.
- **NEVER** use raw unneutralized signals for dollar-neutral portfolios. At minimum sector-demean.
- **NEVER** ignore multiple testing. If you tested N signals, use Benjamini-Hochberg FDR at 5-10% (preferred over Bonferroni). Harvey-Liu-Zhu: new factors need t-stat >= 3.0.
- **NEVER** report Sharpe without: risk-free rate subtracted, autocorrelation check (if rho>0.1, deflate by sqrt((1-rho)/(1+rho))), confidence interval (SE(SR) ~ sqrt((1+SR^2/2)/T_years)).
- **NEVER** ignore survivorship bias. Biased datasets overstate returns by 1.5-2.5% annually. Include delisted securities.

## 3. Factor Reference

### Standard Factors and Typical Monthly IC (US large-cap, 1-month forward)

| Factor | IC Range | Half-Life | Ann. L/S Premium | Key Risk |
|--------|----------|-----------|------------------|----------|
| Value (P/B, EV/EBITDA) | 0.02-0.04 | 12-36 months | 3-6% | Value traps, long drawdowns |
| Momentum (12-1 month) | 0.03-0.05 | ~3 months | 7-9% | Crash risk (-73% in 2009) |
| Quality (ROE, accruals) | 0.02-0.04 | 6-12 months | 3-5% | Low standalone |
| Low Volatility | 0.01-0.03 | 6-24 months | 4-8% | Crowding, rate sensitivity |
| Earnings Revisions | 0.04-0.06 | 1-3 months | 4-7% | Fast decay, cost-sensitive |
| Short Interest (inverse) | 0.02-0.04 | 1-3 months | 6-12% (EW) | Squeeze risk |

### Factor Construction Best Practices
- Winsorize at 1st/99th percentile before ranking
- Cross-sectional z-score per rebalance date (not full-sample)
- Sector-neutralize for L/S strategies (demean within GICS sectors)
- Size-neutralize via regression on log(market cap)
- Match rebalance frequency to ~1/3 of signal half-life

### Factor Combination
- **Default**: Equal-weighted rank composite (hardest to beat, no estimation error)
- **Upgrade**: IC-weighted with 36+ month lookback, constrain weights to [10%, 50%]
- **Avoid**: Optimized weights unless 10+ years of IC history and heavy regularization
- Measure pairwise factor correlation; flag pairs >0.6 for orthogonalization

## 4. Portfolio Construction

### Objective Selection
- **No return forecasts**: Minimum Variance or Risk Parity
- **With return forecasts**: Mean-Variance (lambda 2-5, market-implied ~2.67) or Black-Litterman
- **Non-normal returns**: CVaR optimization (LP formulation, needs scenarios)
- **Maximum Sharpe**: Extremely sensitive to return estimates; use only with shrunk/BL returns

### Standard Constraint Templates

**Dollar-neutral long-short:**
```
NetExposure(-0.05, 0.05)      # near dollar-neutral
GrossExposure(2.0)            # 100/100
PositionLimit(-0.05, 0.05)    # max 5% per name
TurnoverLimit(0.30)           # 30% two-way per rebalance
```

**Long-only constrained:**
```
FullyInvested()
LongOnly()
PositionLimit(0.0, 0.05)     # max 5% per name
SectorLimit(0.30)            # max 30% any sector
TrackingError(0.06)          # 6% TE ceiling
```

### Solver Hierarchy
CLARABEL (default, fast) -> MOSEK (commercial, most robust) -> SCS (large-scale, lower accuracy). Always warm-start from previous solution. If infeasible: bisect constraints to find conflict; relax soft constraints first.

## 5. Covariance Estimation

| Universe Size | Recommended Estimator |
|---------------|----------------------|
| <50 stocks | Sample covariance (with cleaning) |
| 50-500 stocks | Ledoit-Wolf shrinkage (constant-correlation target) |
| 500+ stocks | PCA factor model or commercial risk model (Barra, Axioma) |
| Dynamic/regime | EWMA (vol half-life: 21d, correlation: 63d) |

- Monitor condition number at every rebalance. Flag >1000; add regularization floor.
- For production at >$100M AUM: commercial risk model is almost always justified.
- Nonlinear Ledoit-Wolf (2017) is strictly better than linear shrinkage when N/T > 0.5.

## 6. Risk Management

### Risk Metrics (prefer CVaR over VaR)
- **CVaR/ES**: Expected loss given you're in the tail. Sub-additive, captures severity. Basel III/IV standard.
- **Cornish-Fisher VaR**: Adjusts for skewness/kurtosis. Increases VaR 20-30% vs Gaussian for typical equity portfolios.
- **Max Drawdown**: Report alongside Sharpe always. Calmar = Ann. Return / |MDD|.

### Concentration Thresholds
- Single position >5% of portfolio: flag (long-only); >3% (L/S short leg)
- Effective N positions (1/HHI) < 20: concentrated, requires justification
- Top-5 risk contribution > 35% of total variance: review
- Single factor > 30% of active risk: review unless intentional tilt

### Stress Testing (minimum set)
- GFC: Oct 2007-Mar 2009, SPX -57%, correlations spike to 0.70-0.85
- COVID: Feb-Mar 2020, SPX -34% in 33 days, VIX peaked 82
- Rate Shock: Jan-Oct 2022, SPX -25%, growth/value rotation +40%
- Factor-specific: momentum crash (-3 to -5 SD), value crash (-3 SD)

### Position Limits by Strategy Type
| Strategy | Max Single Name | Net Exposure | Gross Exposure |
|----------|----------------|--------------|----------------|
| Market-neutral L/S | 3-5% | +/-10% | 150-300% |
| Long-biased L/S | 3-7% (L), 2-5% (S) | +20% to +60% | 120-200% |
| Multi-manager pod | 2-4% | +/-20% | 300-600% |
| Long-only active | 2-5% | 100% | 100% |

## 7. Transaction Costs

### Cost Components by Market Cap
| Tier | Spread (1-way) | Round-Trip (all-in) | Short Borrow (ann.) |
|------|---------------|---------------------|---------------------|
| Mega-cap (>$100B) | 0.5-1.5 bps | 3-8 bps | 25-50 bps |
| Large-cap ($10-100B) | 1-5 bps | 5-15 bps | 30-100 bps |
| Mid-cap ($2-10B) | 5-15 bps | 15-30 bps | 50-300 bps |
| Small-cap ($300M-2B) | 10-50 bps | 25-75 bps | 200-500+ bps |

### Market Impact Model
Square root model: `Impact(bps) = eta x sigma x sqrt(Q/V)` where eta=0.5 (large-cap) to 1.0 (small-cap), sigma=daily vol, Q/V=participation rate.

### Alpha Hurdle by Turnover
Net alpha = Gross alpha - (Turnover x RT_Cost). For net alpha of 200bps/yr:
- 50% turnover, 5bps RT: need 202bps gross (easy)
- 200% turnover, 15bps RT: need 230bps gross (moderate)
- 1000% turnover, 15bps RT: need 350bps gross (demanding)

### Capacity Formula
`Capacity = Participation_Rate x Universe_DDTV x 252 / Annual_Turnover`

## 8. ML in Quant Finance

### Validation (most critical section -- wrong validation = meaningless results)
- **Walk-forward**: Train on [t0,t1], test on [t1,t2], expand/roll. Minimum 5 folds.
- **Purged k-fold**: Remove training observations whose label windows overlap with test set. Mandatory for overlapping forward-return labels.
- **Embargo**: Add buffer (63 days for monthly models) between train and test to prevent autocorrelation leakage.
- **CPCV**: Generates distribution of OOS Sharpe ratios, enabling Probability of Backtest Overfitting (PBO) computation. Target PBO < 0.05.

### Model Selection
- **Start with Ridge regression**: Often best at low SNR (R^2 typically 0.01-0.05). Interpretable, stable.
- **LightGBM/XGBoost**: Good for non-linear interactions. Conservative hyperparameters: num_leaves 20-50, min_data_in_leaf 20-50, learning_rate 0.01-0.05, feature_fraction 0.5-0.8.
- **Neural networks**: Rarely outperform trees in US large-cap cross-sectional equity. Consider only for very large feature sets or NLP embeddings.
- **Ensemble/blend**: IC-weighted average of Ridge + LightGBM often best. Simpler than stacking.

### Feature Engineering
- Technical: momentum (12-1mo), volatility, volume patterns. Cross-sectionally rank.
- Fundamental: value ratios, quality metrics, growth. Lag by 60+ days for PIT.
- Always shift(1) minimum for any price-derived feature.
- Add data-staleness feature (days since last filing) for fundamental features.
- Evaluate feature importance OOS, not in-sample (in-sample importance is noise at low SNR).

## 9. Statistical Rigor

### Hypothesis Testing for Signals
- Use **Newey-West HAC** standard errors for IC t-stats (OLS t-stats are inflated by autocorrelation). Lag selection: L = floor(0.75 x T^(1/3)).
- IC series SE under null: ~1/sqrt(N_stocks). For N=500: SE ~ 0.045 per period.
- **Deflated Sharpe Ratio (DSR)**: Corrects for number of trials tested. Require DSR > 0.95 before going live.

### Multiple Testing
- **Benjamini-Hochberg FDR**: Controls expected false discovery proportion at 5-10%. Preferred over Bonferroni (too conservative).
- Practical rule: if you tested 100 signals, effective significance threshold ~ p < 0.005 (not 0.05).
- Track ALL tested variants including abandoned ones. The graveyard counts.

### Key Formulas
- **Fundamental Law**: IR ~ IC x sqrt(BR) x TC. IC=0.05, BR=500 stocks monthly, TC=0.7 -> IR ~ 0.78
- **Sharpe ratio SE**: SE(SR) ~ sqrt((1 + SR^2/2) / T_years). SR=1.0, T=5yr -> SE ~ 0.55. SR=1.0 on 5 years is NOT significantly different from SR=0.5.
- **IC to returns**: IC=0.02 on 1000-stock universe, monthly -> IR ~ 0.63 -> ~3% annual alpha at 5% TE

## 10. Alternative Data

### Honest Assessment by Category
| Data Type | IC Range | Notes |
|-----------|----------|-------|
| Credit card/transactions | Historically high | Compressed edge; broad adoption |
| Short interest (FINRA) | 0.02-0.03 | Reliable negative signal; squeeze prediction is not |
| Earnings call NLP (FinBERT) | 0.01-0.025 | Better for small/mid cap; decays in days for large |
| 10-K tone/readability | 0.01-0.03 | Long horizon; strong academic support |
| Insider Form 4 (open market buys) | 0.02-0.04 | Best insider signal; sells are noisy |
| Satellite (retail parking) | Weakened | Was strong 2011-2018; now widely held |
| Options skew/flow | 0.03-0.06 (5d) | Decays fast; needs real-time infra |
| 13F alpha cloning | 0.01-0.02 | 45-day lag; best-idea concentration helps |

### Integration Rules
- Alt data typically 15-30% of total signal weight (shorter history = higher estimation uncertainty)
- Minimum 3 years history before paying for premium data
- PIT correctness is critical -- snap all timestamps to next valid trading day
- Cost-benefit: IC of 0.01 justifies data cost only for funds >$1B AUM
- Residualize alt signals against traditional factors to confirm genuinely new information

## 11. Workflow Discipline

### Before Backtesting
- Pre-register: universe, rebalance frequency, lookback, signal method, cost model, acceptance thresholds
- Git-commit the pre-registration before running any backtest

### Presentation Checklist
- Cumulative return chart with IS/OOS boundary marked
- Factor exposure time series (market, value, momentum, quality, low-vol)
- Rolling 12-month Sharpe (reveals regime dependence)
- Long/short leg decomposition for L/S strategies
- Transaction cost sensitivity at 1x, 2x, 3x base costs
- Metrics: Sharpe, Sortino, Max DD, Calmar, turnover, capacity, OOS IR

### Production Readiness Gates
- OOS Sharpe > pre-registered threshold, net of realistic costs
- OOS period covers 3+ years including one significant drawdown
- IS-to-OOS Sharpe degradation < 40%
- Capacity > 3x target AUM
- Factor exposures within mandate limits
- Monitoring alerts defined: drawdown, IC drift, factor exposure drift, TE breach
- Graceful degradation plan written (what triggers size reduction, who decides)
