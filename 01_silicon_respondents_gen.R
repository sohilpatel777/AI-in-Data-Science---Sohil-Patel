################################################################################
# 01_silicon_respondents_gen.R
# Synthetic B2B buyers and pricing structure: data generation
#
# HOW TO RUN - 
#
#   Set N_DRAWS (respondents per cell) in the configuration block, then run
#   the whole file. 
#   There are 18 cells, so total calls = 18 x N_DRAWS.
#   Example: N_DRAWS = 2 gives 36 calls, N_DRAWS = 30 gives 540 calls.
#   Outputs: data/responses_<run id>.csv, prompts_<run id>.txt,
#   run_metadata_<run id>.txt, and data/raw/<run id>/<cell>.rds (git ignored).
################################################################################

library(ellmer)      # packageVersion("ellmer") >= 0.4.0
library(httr2)       # only used to list the available models (Lab 5)

# ---- 1. Configuration ---------------------------------------------------------

N_DRAWS        = 30           # respondents (draws) per cell; 18 cells in total
MODEL_KEY      = "mistral"     # "gptoss" (main run) or "mistral" (robustness run)
SCALE_REVERSED = FALSE        # TRUE for the reversed anchor robustness run
TEMPERATURE    = 1
PROMPT_VERSION = "v1"
SEED           = 20261021
BASE           = "https://chat.kiconnect.nrw/api/v1"

MODEL_IDS = c(gptoss  = "openai-gpt-oss-120b",
              mistral = "mistral-small-3-2-24b-instruct-2506")
MODEL = MODEL_IDS[[MODEL_KEY]]


RUN_ID = paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", MODEL_KEY, "_n",
                N_DRAWS, "_seed", SEED,
                if (SCALE_REVERSED) "_reversed" else "")


# Credentials come only from .Renviron (Lab 5). Never type the key in this file

stopifnot(nzchar(Sys.getenv("KICONNECT_API_KEY")))


# Check which models this key can use, and stop early if ours is missing.

available_models = function() {
  m = request(BASE) |>
    req_url_path_append("models") |>
    req_auth_bearer_token(Sys.getenv("KICONNECT_API_KEY")) |>
    req_perform() |>
    resp_body_json()
  vapply(m$data, function(x) x$id, character(1))
}
AVAILABLE_MODELS = available_models()
cat("Models available to this key:\n")
print(AVAILABLE_MODELS)
missing_ids = setdiff(MODEL_IDS, AVAILABLE_MODELS)
if (length(missing_ids) > 0) {
  warning("Not in the model list: ", paste(missing_ids, collapse = ", "))
}
if (!MODEL %in% AVAILABLE_MODELS) {
  stop("Model ", MODEL, " is not available for this key. ",
       "Pick an id from the list above and update MODEL_IDS.")
}


START_TIME = Sys.time()

# Layout: clean outputs in data/, audit files in data/raw/<run id>/

RAW_DIR = file.path("data", "raw", RUN_ID)
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(SEED)

# One new chat object per task, keeping the API stateless

new_chat = function(system_prompt = NULL, model = MODEL,
                    temperature = TEMPERATURE) {
  chat_openai_compatible(
    base_url      = paste0(BASE, "/"),
    credentials   = function() Sys.getenv("KICONNECT_API_KEY"),
    model         = model,
    system_prompt = system_prompt,
    params        = params(temperature = temperature),
    echo          = "none"
  )
}

# ---- 2. Pricing parameters and costs (computed, never typed) -----------------

USERS      = 40
EXP_VOL    = 120000
P_USAGE    = 0.40     # euros per invoice, usage based
P_SEAT     = 100      # euros per user per month, per seat
FEE_HYBRID = 1800     # euros per month, hybrid fixed part
P_HYBRID   = 0.22     # euros per invoice, hybrid variable part

cost_usage  = function(v) v * P_USAGE
cost_seat   = function(v) 12 * USERS * P_SEAT
cost_hybrid = function(v) 12 * FEE_HYBRID + v * P_HYBRID


# Self check: expected annual cost must be 48,000 euros in every condition.

stopifnot(abs(cost_usage(EXP_VOL)  - 48000) < 1e-6,
          abs(cost_seat(EXP_VOL)   - 48000) < 1e-6,
          abs(cost_hybrid(EXP_VOL) - 48000) < 1e-6)

PROFILES = list(
  S = list(low = 80000, high = 160000,
           history = paste0("Over the past three years, yearly volume has ",
                            "varied between 80,000 and 160,000 invoices, ",
                            "depending on orders and the season.")),
  V = list(low = 40000, high = 200000,
           history = paste0("Over the past three years, yearly volume has ",
                            "varied between 40,000 and 200,000 invoices, ",
                            "depending on the timing of large customer ",
                            "projects."))
)

fmt_num = function(x) format(round(x), big.mark = ",", scientific = FALSE,
                             trim = TRUE)
eur  = function(x) paste0("€", fmt_num(x))
unit = function(x) paste0("€", sprintf("%.2f", x))

# ---- 3. Vignette text ---------------------------------------------------------

base_text = function(profile) {
  paste0(
    "Northbridge Components is a manufacturing company with about 400 ",
    "employees. Its finance team has 40 people who process supplier ",
    "invoices. Last year the team handled about ", fmt_num(EXP_VOL),
    " invoices. ", PROFILES[[profile]]$history, "\n\n",
    "Northbridge is considering InvoiceFlow, a service from an established ",
    "software provider. InvoiceFlow automatically reads incoming invoices, ",
    "extracts the key data, codes them to the right accounts and routes ",
    "them for approval. The provider estimates it would cut manual ",
    "processing time by about 60%. The contract runs for 12 months. ",
    "Onboarding, customer support and all software updates are included. ",
    "All prices are in euros and exclude VAT.")
}

pricing_text = function(pricing, profile) {
  lo = PROFILES[[profile]]$low
  hi = PROFILES[[profile]]$high
  switch(pricing,
    usage = paste0(
      "InvoiceFlow charges ", unit(P_USAGE), " for each invoice it ",
      "processes, billed monthly in arrears. Any number of employees can ",
      "use the service. At last year's volume of ", fmt_num(EXP_VOL),
      " invoices, the annual cost would be ", eur(cost_usage(EXP_VOL)),
      ". At ", fmt_num(lo), " invoices it would be ", eur(cost_usage(lo)),
      ", and at ", fmt_num(hi), " invoices it would be ",
      eur(cost_usage(hi)), "."),
    seat = paste0(
      "InvoiceFlow charges ", eur(P_SEAT), " per month for each licensed ",
      "user, billed monthly. Northbridge would license ", USERS,
      " users. There is no limit on the number of invoices processed. The ",
      "annual cost would be ", eur(cost_seat(EXP_VOL)),
      ", whether Northbridge processes ", fmt_num(lo), ", ",
      fmt_num(EXP_VOL), " or ", fmt_num(hi), " invoices."),
    hybrid = paste0(
      "InvoiceFlow charges a fixed platform fee of ", eur(FEE_HYBRID),
      " per month (", eur(12 * FEE_HYBRID), " per year), plus ",
      unit(P_HYBRID), " for each invoice processed, billed monthly in ",
      "arrears. Any number of employees can use the service. At last ",
      "year's volume of ", fmt_num(EXP_VOL), " invoices, the annual cost ",
      "would be ", eur(cost_hybrid(EXP_VOL)), ". At ", fmt_num(lo),
      " invoices it would be ", eur(cost_hybrid(lo)), ", and at ",
      fmt_num(hi), " invoices it would be ", eur(cost_hybrid(hi)), "."),
    stop("unknown pricing condition"))
}


# ---- 4. Personas and system prompt -------------------------------------------

PERSONAS = c(
  P1 = paste0(
    "You are the Chief Financial Officer of Northbridge Components, a ",
    "manufacturing company with about 400 employees. You own the ",
    "company's annual budget and approve software contracts. You answer ",
    "to the CEO for keeping spending within budget and for the accuracy ",
    "of the cost forecast. You judge purchases by their total annual cost ",
    "and their business return. You do not use the invoice system ",
    "yourself."),
  P2 = paste0(
    "You are the Accounts Payable Operations Manager at Northbridge ",
    "Components, a manufacturing company with about 400 employees. You ",
    "lead the finance team of 40 people who process supplier invoices ",
    "every day. You do not own the budget and cannot approve large ",
    "contracts, but you recommend tools and carry responsibility for ",
    "getting invoices processed on time, especially at month end and ",
    "during busy periods. Your team would use the service daily."),
  P3 = paste0(
    "You are the Procurement Manager at Northbridge Components, a ",
    "manufacturing company with about 400 employees. You run vendor ",
    "selection and negotiate software contracts. You are measured on cost ",
    "savings and on avoiding unfavorable contract terms. You compare each ",
    "offer with alternatives on the market and review the total cost over ",
    "the contract term. You will not use the service yourself.")
)

SHARED_INSTRUCTION = paste0(
  "You are taking part in a business survey. Read the offer you are shown ",
  "and answer the questions as the person described above would, based ",
  "only on the information given. Give your honest assessment. There are ",
  "no right or wrong answers.")

build_system = function(persona) {
  paste0(PERSONAS[[persona]], "\n\n", SHARED_INSTRUCTION)
}



# ---- 5. Survey items, user prompt, response schema ---------------------------


ITEMS = c(
  pv1 = paste0("Considering what we would pay and what we would get, this ",
               "offer is good value for our company."),
  pv2 = paste0("The benefits of this service outweigh what we would have to ",
               "give up under this pricing arrangement."),
  pv3 = paste0("Compared with similar offers on the market, this offer ",
               "delivers more value for our money."),
  s1  = "We could forecast our annual spend on this service with confidence.",
  s2  = "The way this service is priced is fair.",
  s3  = paste0("Under this pricing, our costs would rise and fall with how ",
               "much we actually use the service."),
  s4  = paste0("This pricing would let us adjust easily if our needs change ",
               "during the contract."),
  s5  = "I worry that our actual bill could turn out much higher than planned.",
  s6  = paste0("Our employees might hesitate to use the service because each ",
               "use costs money.")
)


build_user = function(profile, pricing, s_order, reversed = FALSE) {
  scale_txt = if (reversed) {
    "from 1 (strongly agree) to 7 (strongly disagree)"
  } else {
    "from 1 (strongly disagree) to 7 (strongly agree)"
  }
  items = c(ITEMS[c("pv1", "pv2", "pv3")], ITEMS[s_order])
  item_lines = paste0(toupper(names(items)), ". ", items, collapse = "\n")
  paste0(
    base_text(profile), "\n\n", pricing_text(pricing, profile), "\n\n",
    "Please answer the following questions about this offer.\n\n",
    "Question 0. According to the offer, how is the annual fee determined?\n",
    "A. By the number of invoices processed\n",
    "B. By the number of licensed users\n",
    "C. By a fixed monthly fee plus the number of invoices processed\n",
    "D. The offer does not say\n\n",
    "Now rate each statement ", scale_txt, ". Use the field with the same ",
    "name as the statement.\n", item_lines, "\n\n",
    "Finally, give one sentence explaining your overall view of this offer.")
}

rating = function(id) type_enum(as.character(1:7),
                                paste("Rating for statement", id))

type_survey = type_object(
  check  = type_enum(c("A", "B", "C", "D"),
                     "Answer to Question 0 about how the fee is determined"),
  pv1 = rating("PV1"), pv2 = rating("PV2"), pv3 = rating("PV3"),
  s1  = rating("S1"),  s2  = rating("S2"),  s3  = rating("S3"),
  s4  = rating("S4"),  s5  = rating("S5"),  s6  = rating("S6"),
  reason = type_string("One sentence on the overall view of the offer")
)

RATING_COLS = c("pv1", "pv2", "pv3", paste0("s", 1:6))
CHECK_KEY   = c(usage = "A", seat = "B", hybrid = "C")


# ---- 6. Design: 2 profiles x 3 pricing x 3 personas x draws ------------------

cells = expand.grid(profile = c("S", "V"),
                    pricing = c("usage", "seat", "hybrid"),
                    persona = c("P1", "P2", "P3"),
                    stringsAsFactors = FALSE)
cells$cell_id = paste(cells$profile, cells$pricing, cells$persona, sep = "_")

resp = cells[rep(seq_len(nrow(cells)), each = N_DRAWS), ]
resp$draw = rep(seq_len(N_DRAWS), times = nrow(cells))
resp$respondent_id = paste0(resp$cell_id, "_", sprintf("%02d", resp$draw))

orders = replicate(nrow(resp), sample(paste0("s", 1:6)), simplify = FALSE)
resp$item_order = vapply(orders, paste, character(1), collapse = ",")

resp$prompt = mapply(function(p, pr, o) build_user(p, pr, o, SCALE_REVERSED),
                     resp$profile, resp$pricing, orders, USE.NAMES = FALSE)


# Self check before any call: costs in the text match the formulas

stopifnot(grepl("48,000", resp$prompt[1], fixed = TRUE))

cat("Run id:", RUN_ID, "\nModel:", MODEL, "\nRespondents:", nrow(resp),
    "\nCells:", nrow(cells), "\n\n")

# Save the exact prompts of the first respondent in each cell (reproducibility)

prompt_dump = unlist(lapply(unique(resp$cell_id), function(cid) {
  r = resp[resp$cell_id == cid, ][1, ]
  c(paste0("=== ", cid, " ==="), "[SYSTEM]", build_system(r$persona),
    "[USER]", r$prompt, "")
}))
writeLines(prompt_dump, file.path("data", paste0("prompts_", RUN_ID, ".txt")))


# ---- 7. API calls -------------------------------------------------------------

# One definition of a valid response, used for the final data
is_valid_raw = function(d) {
  ok = vapply(RATING_COLS, function(cn) {
    x = suppressWarnings(as.integer(d[[cn]]))
    !is.na(x) & x >= 1 & x <= 7
  }, logical(nrow(d)))
  ok = matrix(ok, nrow = nrow(d))
  rowSums(ok) == 9 & d$check %in% c("A", "B", "C", "D") &
    !is.na(d$reason) & nzchar(as.character(d$reason))
}

run_cell = function(rows) {
  t0 = Sys.time()
  cell_error = NA_character_
  chat = new_chat(build_system(rows$persona[1]))
  res = tryCatch(
    parallel_chat_structured(chat, as.list(rows$prompt), type = type_survey,
                             include_tokens = TRUE, max_active = 3,
                             on_error = "continue"),
    error = function(e) e)
  if (inherits(res, "error")) {
    cell_error = conditionMessage(res)
    message("Cell ", rows$cell_id[1], " failed: ", cell_error)
    res = NULL
  }
  secs = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  saveRDS(list(system = build_system(rows$persona[1]),
               prompts = rows$prompt, result = res, seconds = secs),
          file.path(RAW_DIR, paste0(rows$cell_id[1], ".rds")))
  if (is.null(res)) {
    res = data.frame(check = rep(NA_character_, nrow(rows)))
  }
  for (cn in c(RATING_COLS, "reason", "input_tokens", "output_tokens")) {
    if (is.null(res[[cn]])) res[[cn]] = NA
  }
  out = data.frame(respondent_id = rows$respondent_id,
                   check = as.character(res$check),
                   res[RATING_COLS], reason = as.character(res$reason),
                   input_tokens = res$input_tokens,
                   output_tokens = res$output_tokens,
                   batch_seconds = round(secs, 1),
                   timestamp = format(t0, "%Y-%m-%d %H:%M:%S"),
                   cell_error = cell_error,
                   stringsAsFactors = FALSE)
  cat(sprintf("Cell %s done in %.1f s\n", rows$cell_id[1], secs))
  out
}

by_cell = split(resp, factor(resp$cell_id, levels = unique(resp$cell_id)))
res_all = do.call(rbind, lapply(by_cell, run_cell))
rownames(res_all) = NULL

# Every requested respondent must be present exactly once
stopifnot(setequal(res_all$respondent_id, resp$respondent_id),
          !anyDuplicated(res_all$respondent_id))

# ---- 8. Validation and tidy dataset ------------------------------------------

dat = merge(resp[, c("respondent_id", "cell_id", "profile", "pricing",
                     "persona", "draw", "item_order")],
            res_all, by = "respondent_id", sort = FALSE)
dat = dat[match(resp$respondent_id, dat$respondent_id), ]

for (cn in RATING_COLS) dat[[cn]] = suppressWarnings(as.integer(dat[[cn]]))

dat$valid = is_valid_raw(dat)


# Reversed scale run: put scores back on the 1 = strongly disagree direction.
# rev(1:7)[x] maps 1 to 7, 2 to 6, and so on.

if (SCALE_REVERSED) {
  for (cn in RATING_COLS) dat[[cn]] = rev(1:7)[match(dat[[cn]], 1:7)]
}

dat$check_pass  = dat$check == CHECK_KEY[dat$pricing]
dat$pv_mean     = rowMeans(dat[c("pv1", "pv2", "pv3")])
dat$run_id      = RUN_ID
dat$model       = MODEL
dat$temperature = TEMPERATURE
dat$prompt_version  = PROMPT_VERSION
dat$scale_reversed  = SCALE_REVERSED
dat$seed            = SEED

# Reverse worded items (s5, s6) are kept in the original direction here.
# Recoding for analysis is done in the analysis script.Thisforms the DATA file

out_file = file.path("data", paste0("responses_", RUN_ID, ".csv"))
write.csv(dat, out_file, row.names = FALSE)

# Run metadata (reproducibility)
writeLines(c(
  paste("run_id:", RUN_ID), paste("model:", MODEL),
  paste("temperature:", TEMPERATURE),
  paste("prompt_version:", PROMPT_VERSION), paste("seed:", SEED),
  paste("scale_reversed:", SCALE_REVERSED), paste("draws_per_cell:", N_DRAWS),
  paste("start:", format(START_TIME, "%Y-%m-%d %H:%M:%S")),
  paste("end:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste("R:", R.version.string),
  paste("ellmer:", as.character(packageVersion("ellmer")))),
  file.path("data", paste0("run_metadata_", RUN_ID, ".txt")))

cat("\n---- SUMMARY ----\n")
cat("Requested:", nrow(resp), "\n")
cat("Valid:    ", sum(dat$valid), " (", round(100 * mean(dat$valid), 1), "%)\n",
    sep = "")
cat("Manipulation check passed (valid rows):\n")
print(round(tapply(dat$check_pass[dat$valid], dat$pricing[dat$valid], mean), 2))
cat("Saved:", out_file, "\n")
