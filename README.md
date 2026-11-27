# Lead Intake Demo

An AI extracts a commercial insurance intake form from a call transcript, but the AI never gets the final say.

Every field is either **proven correct by deterministic code against the transcript**, or **approved by a human broker**. Only then is a submission built, and it must pass a JSON Schema before it can be sent anywhere.

## Pipeline

1. **Agent extraction:** transcript → raw JSON. `Extractor` sends the transcript to a local Ollama model, which returns, for each of 13 fields, a `value`, a `source_quote` and `all_mentions` (every verbatim quote mentioning the field). `FieldChecker` sorts each field into **Verified** or **Needs approval**, with a plain-English reason for every check that failed.
2. **Broker review:** one click confirms all verified fields; each needs-approval field is approved as-is, edited, or marked not provided. Any field can be edited.
3. **Build:** once all 13 fields are resolved, **Approve and build submission** turns the broker-approved values into the submission JSON (`SubmissionBuilder`): integers for numbers, an array for coverage types, `YYYY-MM-DD` for the date, `null` for "Not provided". A value that can't be converted is kept raw, never guessed or fixed.
4. **Deterministic check:** `SubmissionValidator` validates the submission JSON against `config/schemas/submission_v1.json`. If it fails, nothing is saved: the review page lists each failing field in plain English and highlights its row. If it passes, the submission is saved and shown on the **Ready to send** page.
5. **Channel choice:** on the Ready to send page, send the submission to a carrier by API, portal bot or email (see [Channels](#channels)).

The raw JSON is the model's claim. The submission JSON is the broker-approved record, and is the only thing that will ever leave the app.

## Running it

Requirements: Ruby 4.0, Rails 8, and [Ollama](https://ollama.com) with `granite4.2:8b` pulled.

On a new Mac, `./install.sh` sets all of that up: Ruby 4.0, Ollama running in the background, the Granite model, the gems and the database. It skips anything already installed. Homebrew is optional: if it's installed, Ruby and Ollama come from it (and it's added to `~/.zprofile`); if not, the script offers to install it. Without Homebrew, Ruby is installed with mise or rbenv if you have one (otherwise the script says what to install), and Ollama comes from [ollama.com/download](https://ollama.com/download). Ollama itself is optional too: without it the samples use built-in fixtures.

```sh
./install.sh            # one-time setup on a new Mac
./run.sh                # installs gems, prepares the database, starts http://localhost:3000
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
- **Mark not provided** clears the value. The schema requires every field, so a "Not provided" field blocks the build until the broker edits in a value.
- Approve and Mark not provided are one-time decisions. Edit is available on every field, resolved or not.
- **Approve and build submission** is disabled until all fields are resolved, and the server refuses the build with **422** regardless of what the UI shows.
- Editing any field after a submission is built clears it; the broker must build again.

## Submission schema

`config/schemas/submission_v1.json` (JSON Schema 2020-12) is the contract:

- every field required and non-null; `additionalProperties: false` at every level
- FEIN `^\d{2}-\d{7}$`, NAICS `^\d{6}$`, ZIP `^\d{5}$`
- annual revenue, employee count, years in business: integers, minimum 1
- coverage types: a non-empty array of non-empty strings
- effective date `format: date`, contact email `format: email`

The schema checks format only. Value checks like "date not in the past" stay in the review stage.

## Channels

Three mock carriers live inside this app (`app/controllers/mock_carriers/`, under `/mock_carriers`). They stand in for real carrier systems and share nothing with the channel code except a small deterministic pricing module (`MockCarriers::Pricing`). The channels call them over real HTTP at `MOCK_CARRIER_BASE_URL` (default `http://localhost:3000`). The dev server runs 3 Puma threads, so the app can call itself.

Before any channel runs, the stored submission JSON is re-validated against the schema, and the channel refuses (422) if it fails or the submission is no longer ready. Each attempt is saved as a `QuoteRequest` (quoted / declined / referred / sent / failed) and added to the Quote requests list. Channels never raise to the UI: timeouts, bad responses and unexpected pages become `failed` with a clear message.

| Channel | Mock carrier | How it works |
| --- | --- | --- |
| `Channels::Api` | **Acme Insurance**: JSON API at `POST /mock_carriers/acme/api/v1/quotes`, bearer token (`ACME_API_TOKEN`, default `acme-demo-token`) | Maps the submission JSON to Acme's field names, POSTs it, and interprets 201 quoted / 200 declined or referred / 401 / 422 / 503. A business named "Acme Test Outage" triggers the 503. |
| `Channels::Portal` | **Beacon Mutual**: HTML broker portal with session login (`BEACON_USERNAME` / `BEACON_PASSWORD`, default `broker` / `beacon-demo`) | A Mechanize bot logs in, fills the application form by field name (`950,000` sales, `MM/DD/YYYY` date), ticks coverage checkboxes by label text, submits, and parses the result page. A coverage with no checkbox (e.g. commercial auto, cyber) stops it before submitting. The row's **Steps / scraped** section shows each request and status, every field filled (and where in the submission JSON it came from), and each value read from the result page with its HTML. The password and cookies are never recorded. |
| `Channels::Email` | **Northwind Specialty**: `submissions@northwind.test` | Emails a plain-text summary with the application PDF attached. In development emails are written to `tmp/mails`. The row's **Sent** section shows the headers, body and attachment exactly as sent; the attachment links to the stored PDF bytes. Status is `sent`, "Awaiting carrier reply"; no reply is simulated. |

Both quoting carriers use the same rules: decline any coverage they don't offer, refer annual revenue over $5,000,000, otherwise quote. Each channel translates our coverage names (e.g. "workers compensation") into its carrier's vocabulary ("workers comp", "Workers Comp").

**Trade-offs.** The API is fast and structured: typed fields, explicit status codes, and an unambiguous result. The portal bot works where a carrier has no API, but it depends on page layout: a renamed field, label or result table breaks it, which is why it checks every step and fails loudly. Email works with any carrier, but nothing comes back automatically: the outcome depends on a human replying.

## Why

**The model's output is treated as a claim to be proven, not an answer.** A field is never trusted because the model said so, only because code proved it against the transcript or a human approved it.

That's why the model is never asked for a confidence score: a model's opinion of itself is just another unverified claim. A quote is useful because code can check it. If the quote isn't in the transcript, or the value isn't in the quote, the claim fails, however confident the model sounded.

The samples show this:

- **Northgate Dental (happy path):** everything is stated plainly, and every field verifies except years in business, which always needs a broker. Acme and Beacon both quote it.
- **Hudson Millwork (AI caught):** a noisy call. The FEIN is spoken as words, the NAICS code is never given, revenue is in words, the employee count is corrected mid-call (38, then 41), a second location's ZIP is mentioned, the start date is "the first of April next year", and the email is spelled out. Code can prove none of those, so all eight go to the broker. Revenue over $5M means both quoting carriers refer it.
- **Lumen Analytics (channels differ):** clean, except a ZIP+4 (`07302-3911`) that fails the 5-digit rule. Once fixed, Acme quotes it, but Beacon's portal has no cyber checkbox, so the bot stops before submitting.

The pipeline keeps three roles apart:

- **The model's output is a claim.** It is never sent anywhere.
- **The broker approves the values.** Code proves what it can against the transcript; a human decides the rest.
- **The JSON Schema is the contract.** Whatever channel carries a submission to a carrier (email PDF, portal bot or API) can rely on the same validated, typed record, without re-checking the transcript or trusting the model.

The checks are conservative on purpose. A false "needs approval" costs a broker a click; a false "verified" puts wrong data on an application.

Fields that require interpretation (like durations relative to the call date) are never auto-verified.

## Code map

- `app/models/extractor.rb`: all Ollama code (Net::HTTP, JSON schema, defensive parsing, fixture fallback)
- `app/models/field_checker.rb`: the categorisation rules and format validation
- `app/models/submission.rb`: the field structure and review rules
- `app/models/submission_builder.rb`: approved values → typed submission JSON
- `app/models/submission_validator.rb` and `config/schemas/submission_v1.json`: the schema check and its plain-English errors
- `app/models/submission_pdf.rb`: the Prawn PDF, built from the submission JSON for the email channel
- `app/models/channels/`: the API, portal bot and email channels; `app/models/quote_request.rb` records each attempt
- `app/controllers/mock_carriers/`: the fake Acme API, Beacon portal and shared pricing
- `config/samples/`: sample transcripts and fixture extractions

## Next steps (not built)

- Duplicate submission check before carrier submission
- ACORD 125 export
- Tracking how often brokers edit each field, to find where extraction is weakest
