################################################################################
# 02_analysis.R
# Synthetic B2B buyers and pricing structure: analysis of perceived value
#
# HOW TO RUN: run the whole file from the repository root. No API calls.
# One specification is analysed per call of run_spec(). To add another one
# (for example Mistral, or a reversed run), add one more spec list at the
# bottom of the file and call run_spec() on it.
#
# Outcome: pv_mean (mean of pv1 to pv3, 1 to 7, higher = more perceived value).
# Only rows with valid == TRUE are analysed.
# Scores of reversed runs are already recoded to the normal direction by
# 01_silicon_respondents_gen.R, so ratings are never recoded here.
################################################################################

library(ggplot2)

# ---- 1. Configuration ---------------------------------------------------------

N_BOOT     = 2000        # bootstrap resamples per cell
BOOT_SEED  = 20261021    # one fixed seed for all resampling
N_EXPECTED = 540         # 2 profiles x 3 pricing x 3 personas x 30 draws

PRICING_LEVELS = c("usage", "seat", "hybrid")

# The three contrasts: first name minus second name
CONTRASTS = list(
  "usage minus seat"   = c("usage", "seat"),
  "usage minus hybrid" = c("usage", "hybrid"),
  "hybrid minus seat"  = c("hybrid", "seat")
)

# One specification = the data we want and where to put the results
SPEC_GPTOSS_NORMAL = list(
  name     = "gptoss_normal",
  model    = "openai-gpt-oss-120b",
  reversed = FALSE
)

# ---- 2. Finding and preparing the data ---------------------------------------

# Read the CSV files in data/ and keep the ones that match the specification.
# Matching uses the contents of the columns model and scale_reversed and the
# number of rows, never the file name.
find_data = function(spec, data_dir = "data") {
  files = list.files(data_dir, pattern = "^responses_.*[.]csv$",
                     full.names = TRUE)
  candidates = list()
  for (f in files) {
    d = read.csv(f, stringsAsFactors = FALSE)
    ok = all(c("model", "scale_reversed", "valid", "run_id") %in% names(d)) &&
      nrow(d) == N_EXPECTED &&
      all(d$model == spec$model) &&
      all(as.logical(d$scale_reversed) == spec$reversed)
    if (ok) {
      candidates[[f]] = list(file = f, run_id = d$run_id[1],
                             n_valid = sum(d$valid), data = d)
    }
  }
  if (length(candidates) == 0) {
    stop("No file in ", data_dir, " has model ", spec$model,
         ", scale_reversed ", spec$reversed, " and ", N_EXPECTED, " rows. ",
         "Please generate this run with 01_silicon_respondents_gen.R ",
         "(MODEL_KEY for ", spec$model, ", SCALE_REVERSED = ", spec$reversed,
         ", N_DRAWS = 30).")
  }
  # Most valid rows first, then the latest run_id
  n_valid = vapply(candidates, function(x) x$n_valid, numeric(1))
  run_ids = vapply(candidates, function(x) x$run_id, character(1))
  best = candidates[[order(-n_valid, -rank(run_ids))[1]]]
  cat("Qualifying files:", length(candidates), "\n")
  cat("Chosen file:", best$file, "\n")
  cat("Run id:", best$run_id, "  valid rows:", best$n_valid, "of",
      nrow(best$data), "\n\n")
  best$data
}

# Add the reverse scored versions of s5 and s6 (8 minus score) for later use.
# No output uses them yet.
add_reversed_items = function(d) {
  d$s5_rev = 8 - d$s5
  d$s6_rev = 8 - d$s6
  d
}

# ---- 3. Bootstrap -------------------------------------------------------------

# Resample the valid pv_mean values inside each cell N_BOOT times.
# Result: a matrix with one row per resample and one column per cell, holding
# the resampled cell mean. Every interval in this script is computed from this
# one matrix, so all intervals use the same resamples.
bootstrap_cells = function(valid_data, n_boot = N_BOOT, seed = BOOT_SEED) {
  set.seed(seed)
  values = split(valid_data$pv_mean, valid_data$cell_id)
  boot_one_cell = function(x) {
    picks = sample.int(length(x), length(x) * n_boot, replace = TRUE)
    colMeans(matrix(x[picks], nrow = length(x)))
  }
  sapply(values, boot_one_cell)
}

# 95 percent percentile interval of a vector of bootstrap values
interval95 = function(x) quantile(x, c(0.025, 0.975), names = FALSE)

# ---- 4. Cell table ------------------------------------------------------------

make_cell_table = function(all_data, valid_data, boot) {
  cell_ids = colnames(boot)
  one_row = function(cid) {
    x = valid_data$pv_mean[valid_data$cell_id == cid]
    info = all_data[all_data$cell_id == cid, ][1, ]
    ci = interval95(boot[, cid])
    data.frame(cell_id = cid, profile = info$profile, pricing = info$pricing,
               persona = info$persona,
               n_requested = sum(all_data$cell_id == cid),
               n_valid = length(x),
               mean = mean(x), median = median(x), sd = sd(x),
               ci_low = ci[1], ci_high = ci[2],
               all_identical = length(unique(x)) == 1,
               stringsAsFactors = FALSE)
  }
  tab = do.call(rbind, lapply(cell_ids, one_row))
  tab$pricing = factor(tab$pricing, levels = PRICING_LEVELS)
  tab = tab[order(tab$persona, tab$profile, tab$pricing), ]
  tab$pricing = as.character(tab$pricing)
  rownames(tab) = NULL
  tab
}

# ---- 5. Contrast table --------------------------------------------------------

# Mean of pv_mean for one pricing model over a set of cells, together with its
# bootstrap values. Cells are weighted by their number of valid rows, which is
# the same as the plain mean of all valid rows in those cells.
pooled_mean = function(cell_tab, boot, pricing, rows) {
  cells = cell_tab[rows & cell_tab$pricing == pricing, ]
  w = cells$n_valid / sum(cells$n_valid)
  list(estimate = sum(w * cells$mean),
       boot = as.vector(boot[, cells$cell_id, drop = FALSE] %*% w))
}

# The three contrasts for one group of cells (all cells, or one block)
contrasts_for = function(cell_tab, boot, rows, scope, persona, profile) {
  out = lapply(names(CONTRASTS), function(cn) {
    a = pooled_mean(cell_tab, boot, CONTRASTS[[cn]][1], rows)
    b = pooled_mean(cell_tab, boot, CONTRASTS[[cn]][2], rows)
    ci = interval95(a$boot - b$boot)
    data.frame(scope = scope, persona = persona, profile = profile,
               contrast = cn, estimate = a$estimate - b$estimate,
               ci_low = ci[1], ci_high = ci[2],
               excludes_zero = ci[1] > 0 | ci[2] < 0,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

make_contrast_table = function(cell_tab, boot) {
  everything = rep(TRUE, nrow(cell_tab))
  parts = list(contrasts_for(cell_tab, boot, everything, "overall", "all", "all"))
  for (pe in sort(unique(cell_tab$persona))) {
    for (pr in sort(unique(cell_tab$profile))) {
      rows = cell_tab$persona == pe & cell_tab$profile == pr
      parts[[length(parts) + 1]] =
        contrasts_for(cell_tab, boot, rows, "block", pe, pr)
    }
  }
  tab = do.call(rbind, parts)
  rownames(tab) = NULL
  tab
}

# ---- 6. Chart -----------------------------------------------------------------

plot_cells = function(cell_tab, valid_data, title) {
  cell_tab$pricing = factor(cell_tab$pricing, levels = PRICING_LEVELS)
  valid_data$pricing = factor(valid_data$pricing, levels = PRICING_LEVELS)
  dodge = 0.6
  ggplot() +
    # faint raw draws behind, jittered (fixed seed keeps the chart reproducible)
    geom_point(data = valid_data,
               aes(x = pricing, y = pv_mean, color = profile),
               position = position_jitterdodge(jitter.width = 0.15,
                                               jitter.height = 0,
                                               dodge.width = dodge,
                                               seed = 1),
               alpha = 0.2, size = 1) +
    # cell mean with its bootstrap interval in front
    geom_pointrange(data = cell_tab,
                    aes(x = pricing, y = mean, ymin = ci_low, ymax = ci_high,
                        color = profile),
                    position = position_dodge(width = dodge),
                    size = 0.5) +
    facet_wrap(~ persona, nrow = 1) +
    scale_y_continuous(limits = c(1, 7), breaks = 1:7) +
    labs(title = title, x = "Pricing model",
         y = "Perceived value (pv_mean, 1 to 7)", color = "Company profile",
         caption = paste0("Intervals are 95% bootstrap intervals and reflect ",
                          "random variation in the model's answers only.")) +
    theme_minimal()
}

# ---- 7. One specification from start to finish --------------------------------

run_spec = function(spec) {
  out_dir = file.path("results", spec$name)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  all_data = add_reversed_items(find_data(spec))
  valid_data = all_data[all_data$valid, ]

  boot = bootstrap_cells(valid_data)
  cell_tab = make_cell_table(all_data, valid_data, boot)
  contrast_tab = make_contrast_table(cell_tab, boot)

  write.csv(cbind(cell_tab[1:5], round(cell_tab[6:11], 4),
                  all_identical = cell_tab$all_identical),
            file.path(out_dir, "cell_table.csv"), row.names = FALSE)
  write.csv(cbind(contrast_tab[1:4], round(contrast_tab[5:7], 4),
                  excludes_zero = contrast_tab$excludes_zero),
            file.path(out_dir, "contrast_table.csv"), row.names = FALSE)
  ggsave(file.path(out_dir, "pv_mean_chart.png"),
         plot_cells(cell_tab, valid_data, paste("Perceived value:", spec$name)),
         width = 10, height = 4.5, dpi = 150)

  cat("Cells:", nrow(cell_tab), " valid rows used:", nrow(valid_data), "\n")
  cat("Cells with identical draws:", sum(cell_tab$all_identical), "\n")
  cat("Results written to", out_dir, "\n")
  invisible(list(cells = cell_tab, contrasts = contrast_tab))
}

# ---- 8. Run -------------------------------------------------------------------

res_gptoss_normal = run_spec(SPEC_GPTOSS_NORMAL)
