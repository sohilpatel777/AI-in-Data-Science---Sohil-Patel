# B2B SaaS Buyers and Pricing Structure

Course project for Generative AI for Data Science, University of Cologne, Winter 2026/27.
Author: Sohil Patel. Date: 21 October 2026.

A small study in which language models play B2B software buyers and rate a fictional invoice processing service under three pricing structures. It is a pilot with no human validation. All results (failed) are hypotheses for later testing with real buyers.

## 1. Research question

B2B SaaS is currently undergoing transition in their pricing structures. The trend is shifting from per seat pricing to usage and outcome based pricing. SaaS businesses who figure out the secret sauce to pricing would reap the most benefits while staying competitve. However, the secret sauce is still a big question. Research so far has focused mainly on 2 part tariffs, 3 part tariffs and their implications on usage. However usage is dependent on customer perception of the service value. Moreover, most of this research is in B2C spectrum and not B2B, where the decision making is more rational and has different motives. Hence it is imperative to understand what pricing sturcture is vlaued the most by B2B SaaS customers. We take the first step in this direction to answer:

**At equal expected annual cost, does pricing structure (usage based, per seat, hybrid) change the perceived value reported by (synthetic) B2B buyers?**

*Usage based pricing* is where the customer is priced based on usage. 
e.g. 0.5€ per 1000.000 tokens 

*Per Seat* is when there is a fixed fee for one seat. 
e.g. 40€ per month per employee for a Software solution.

*Hybrid* is when there is a combination of both. Per seat till a threshold and then usage based pricing. 



## 2. Design AND Data in brief

1. Service: InvoiceFlow (fictional). Buyer company: Northbridge Components (fictional)

2. Pricing at equal expected cost of 48,000 euros per year (120,000 invoices, 40 users):
   1. Usage based: 0.40 euros per invoice.
   2. Per seat: 100 euros per user per month.
   3. Hybrid: 1,800 euros per month plus 0.22 euros per invoice.

3. Profiles: Stable volume (80,000 to 160,000 invoices) and Volatile volume (40,000 to 200,000 invoices).

4. Personas: CFO, Accounts payable operations manager, Procurement manager.

5. Cells: 2 profiles x 3 pricing models x 3 personas = 18. Draws per cell: 30. Requests per run: 540.

6. Primary outcome: perceived value, the mean of three items (PV1 to PV3) on a 7 point scale. Secondary items S1 to S6 (predictability, fairness, alignment, flexibility, cost overrun risk, usage hesitation) are descriptive and are not used for results

*Data is generated using silicon respondents for the matrix configuration mentioned in 5. and through vignette and questions consisting of the items mentioned in 6.*
 Every respondent is a fresh API call. The persona is in the system prompt. The vignette and questions are in the user prompt. Temperature is 1. The order of S1 to S6 is random per respondent.

*We use Four runs (specifications) to produce 4 diverse set of data for synthetic respondents*

   1. GPT OSS 120B, normal scale (main run).
   2. GPT OSS 120B, reversed scale anchors.
   3. Mistral Small 3.2 24B, normal scale.
   4. Mistral Small 3.2 24B, reversed scale anchors.

*Technical detials on the data (can be skipped if not essential)*

1. Each run writes one CSV with 540 rows (one row per synthetic respondent).
2. Run ID format: `<date>_<time>_<model key>_n<draws>_seed<seed>`, plus `_reversed` for the reversed scale run. Example: `20261021_165151_gptoss_n30`.
3. Main columns: respondent_id, cell_id, profile, pricing, persona, draw, item_order, check, pv1 to pv3, s1 to s6, reason, tokens, timestamp, valid, check_pass, pv_mean, and run settings (model, temperature, prompt_version, scale_reversed, seed).
4. The CSV keeps the raw answers. In the reversed scale run, answers are recoded to the normal direction before saving. Items S5 and S6 are reverse worded and are flipped in the analysis script (8 minus the score).
5. A response is valid if it has nine integer ratings from 1 to 7, a check answer from A to D and a non empty reason. Invalid rows are flagged and excluded. They are not retried automatically.
6. `data/raw/` is git ignored. Everything else in `data/` is committed, so the analysis can be rerun from the repository alone.

## 2a. Repository structure

    01_silicon_respondents_gen.R    generation script (API calls)
    02_analysis.R                   analysis script (tables and charts)
    data/
      responses_<run id>.csv        one file per run, the analysed dataset
      prompts_<run id>.txt          exact prompts used
      run_metadata_<run id>.txt     settings, package versions, times
      raw/<run id>/<cell>.rds       per cell audit files (git ignored)
    outputs/                        tables and charts [CONFIRM: folder name]



## 3. Workflow

I used AI at every stage but made the decisions myself. For ideation, Claude and ChatGPT generated 20 candidate questions from two prompts; I compared and critiqued them and chose the question. For the literature, two LLMs found about 15 references each; I checked that every paper exists, says what the LLM claimed and is relevant, keeping 4. For data, I generated synthetic respondents: GPT OSS 120B answered one API call per respondent, 540 per run across 18 design cells. The code came from vibe coding with Claude Code, which I then reviewed against the study design to confirm that prompts, cells and scales matched the specs, tested with pilot and full runs, and versioned with manual commits. Every API call is logged with its prompts, settings and run ID, so the design can be rerun, though not the exact answers. For writing, I aligned my notes with Claude, edited its bullets, had it build the slides in cycles, and made the final edit by hand.



## 4. Reproduction steps

Requirements: R (4.3 or newer recommended) and RStudio

1. Clone the repository and open the project folder in RStudio.

2. Install the packages: `install.packages(c("ellmer", "httr2", "dplyr", "tidyr", "ggplot2", "readr", "purrr"))`. 

3. Analysis only (no API key needed, exact reproduction):
   1. Open `02_analysis.R` and run it from the project root.
   2. It reads the committed CSVs in `data/` and writes tables and charts to the output folder.
   3. The bootstrap is seeded (B = 2000), so the intervals are identical on every run.

4. New data generation (needs access to KI:connect):

   1. Create a key in KI:connect and add `KICONNECT_API_KEY=your_key` to your `.Renviron`. Restart R. Never put the key in a script.
   2. Open `01_silicon_respondents_gen.R` and set `MODEL_KEY` (`"gptoss"` or `"mistral"`), `SCALE_REVERSED` (`FALSE` or `TRUE`) and `N_DRAWS` in the configuration block.
   3. Run the script. A full run of 540 requests took about 50 minutes for GPT OSS.
   4. The new files appear in `data/` under a new run ID.

*What reproduces and what does not: model answers are random (temperature 1), so a new generation run will give similar but not identical data. The committed CSVs are the fixed input of the study. The generation was not repeated with a second seed.*



## 5. AI use statement

AI as expected is used for this project. I have specified below as how, when and which AI tools I have utilized in this project.

1. **Study subjects:** the synthetic respondents are GPT OSS 120B and Mistral Small 3.2 24B, accessed through the KI:connect API. They generate the data and are the object of the study.

2. **Coding and writing help:** Claude (Anthropic).
   1. Claude Code in VS Code, plan mode, model - Sonnet 5.5, for the analysis script `02_analysis.R`. One prompt per version, saved in `prompts/`.
   2. A Claude chat session (Claude Sonnet 5.5) for ideating vignettes, personas, items, the generation script `01_silicon_respondents_gen.R`, documentation and slide text.

3. Human role: the researchers set the research question and design, approved every step, ran all code themselves, made all Git commits and are responsible for the results. AI generated code was checked by skimming and by testing the output, not by line by line review. The AI did not run any Git command.

4. All data come from the logged LLM API runs


## 6. References

The literature behind the outcome measure and pricing context is listed in the report.

Ascarza, E., Lambrecht, A., & Vilcassim, N. (2012). When Talk Is “Free”: The Effect of Tariff Structure on Usage Under Two- and Three-Part Tariffs. Journal of Marketing Research (JMR), 49(6), 882–899.

Iyengar, R., Jedidi, K., Essegaier, S., & Danaher, P. J. (2011). The Impact of Tariff Structure on Customer Retention, Usage, and Profitability of Access Services. Marketing Science, 30(5), 820–836.

Nevo, A., Turner, J. L., & Williams, J. W. (2016). Usage-Based Pricing and Demand for Residential Broadband. Econometrica, 84(2), 411–443.

Schlereth, C., Skiera, B., & Wolk, A. (2011). Measuring Consumers’ Preferences for Metered Pricing of Services. Journal of Service Research, 14(4), 443–459.
