# Lead Intake Demo

An AI extracts a commercial insurance intake form from a call transcript, but the AI never gets the final say.

Every field is either **proven correct by deterministic code against the transcript**, or **approved by a human broker**. Only then can a clean, standardised PDF be downloaded.

## How it works

1. Paste a call transcript (or load one of three samples) and click **Extract**.
2. `Extractor` sends it to a local Ollama model, which returns, for each of 13 fields, a `value`, a `source_quote` and `all_mentions` (every verbatim quote mentioning the field).
3. `FieldChecker` sorts each field into **Verified** or **Needs approval**, with a plain-English reason for every check that failed.
4. The broker reviews: one click confirms all verified fields; each needs-approval field is approved as-is, edited, or marked not provided.
5. Once all 13 fields are resolved, **Download PDF** produces a standardised Commercial Insurance Application.

## Running it

Requirements: Ruby 4.0, Rails 8, and [Ollama](https://ollama.com) with `granite4.2:8b` pulled.

```sh
bundle install
bin/rails db:prepare
bin/rails server        # http://localhost:3000
bin/rails test          # fast and offline; never calls Ollama
```

Configuration (optional):

| Variable       | Default                  |
| -------------- | ------------------------ |
| `OLLAMA_URL`   | `http://localhost:11434` |
| `OLLAMA_MODEL` | `granite4.2:8b`          |

If Ollama is unreachable, the three sample transcripts fall back to hardcoded fixture extractions (`config/samples/*.json`) and the review page says so. Any other transcript comes back with every field empty, needing approval.

Extraction runs synchronously and can take up to a minute on a laptop.

## Categorisation rules

A field is **Verified** only if all of these hold:

1. The value is not null.
2. The `source_quote` is found in the transcript, after normalising case, whitespace and punctuation (matched on word boundaries).
3. The value appears inside that quote. Numeric fields (FEIN, ZIP, NAICS, years, revenue, employees) compare digits only. Dates match ISO, `M/D/YYYY` or `January 15th, 2027` spellings. Coverage types must each appear.
4. The value passes format validation:
   - FEIN `NN-NNNNNNN`, NAICS 6 digits, ZIP 5 digits
   - years in business, annual revenue, employee count numeric and > 0
   - email in basic email format; effective date a valid `YYYY-MM-DD`, not in the past
5. Every quote in `all_mentions` is found in the transcript, and none contains a different value. Conflicts are detected for structured fields (the numeric fields, email, date), where code can tell values apart. Free-text fields only need their mentions to exist.

Anything else is **Needs approval**, with reasons such as *Not stated in call*, *Quote not found in transcript*, *Value not in quote*, *FEIN format invalid*, *Conflicting mentions in transcript*.

Review rules:

- **Confirm all verified** resolves every verified field in one click and never touches needs-approval fields.
- **Approve as-is** is allowed only if the value passes format validation.
- **Edit** re-validates the new value and keeps the previous one in `original_value`.
- **Mark not provided** clears the value; the PDF prints "Not provided".
- Resolutions are final. Verified fields can only be confirmed.
- The download button is disabled until all fields are resolved, and the server refuses the PDF with **422** regardless of what the UI shows.

## Why

**The model's output is treated as a claim to be proven, not an answer.** A field is never trusted because the model said so, only because code proved it against the transcript or a human approved it.

That's why the model is never asked for a confidence score: a model's opinion of itself is just another unverified claim. A quote is useful because code can check it. If the quote isn't in the transcript, or the value isn't in the quote, the claim fails, however confident the model sounded.

The samples show this:

- **Bakery (clean):** everything is stated plainly and every field verifies.
- **Landscaping (misheard FEIN):** the FEIN is read out awkwardly, so the extracted value has the wrong digit count and fails format validation. The email is never mentioned. Both go to the broker.
- **IT services (messy):** the employee count is corrected mid-call ("about 40... closer to 45 now"), so the mentions conflict. Revenue is given in words, so code can't prove the number. Both go to the broker.

The checks are conservative on purpose. A false "needs approval" costs a broker a click; a false "verified" puts wrong data on an application.

## Code map

- `app/models/extractor.rb`: all Ollama code (Net::HTTP, JSON schema, defensive parsing, fixture fallback)
- `app/models/field_checker.rb`: the categorisation rules and format validation
- `app/models/submission.rb`: the field structure and review rules
- `app/models/submission_pdf.rb`: the Prawn PDF
- `config/samples/`: sample transcripts and fixture extractions

## Next steps (not built)

- Duplicate submission check before carrier submission
- ACORD 125 export
- Tracking how often brokers edit each field, to find where extraction is weakest
