# Lead Intake Demo

An AI extracts a commercial insurance intake form from a sales call transcript, but it never gets the final say. Every value is either proven against the transcript by code or approved by a broker, and the result must pass a JSON Schema before it can reach a carrier.

## Pipeline

```mermaid
%%{init: {"theme": "base", "themeVariables": {"fontFamily": "Inter, Helvetica, Arial, sans-serif", "lineColor": "#64748b", "fontSize": "14px", "edgeLabelBackground": "#ffffff", "textColor": "#334155"}}}%%
flowchart LR
    subgraph CANVAS[" "]
        T([⛁ Call transcript])
        E[✦ AI · Extract fields<br/>Granite via Ollama]
        TC{{⚙ CODE · Transcript check<br/>◆ CHECKPOINT}}
        R{{◉ HUMAN · Broker review<br/>◆ GATE}}
        B[⚙ CODE · Build JSON]
        SC{{⚙ CODE · Schema check<br/>◆ GATE}}
        CH[◉ HUMAN · Choose channel]
        API[⚙ CODE · Acme API client]
        BOT[⚙ CODE · Beacon portal bot]
        EM[⚙ CODE · Email + PDF]
        ACME[(Acme Insurance)]
        BEACON[(Beacon Mutual)]
        NW[(Northwind Specialty)]

        T --> E
        E --> TC
        TC --> R
        R --> B
        B --> SC
        SC --> CH
        SC -. "fails" .-> R
        CH -. "edit values" .-> R
        CH --> API
        API --> ACME
        CH --> BOT
        BOT --> BEACON
        CH --> EM
        EM --> NW

        subgraph LEGEND[" "]
            direction LR
            L1[✦ AI]
            L2[⚙ Code]
            L3[◉ Human]
            L4{{◆ Checkpoint / Gate}}
        end
    end

    classDef input fill:#f1f5f9,stroke:#94a3b8,color:#334155
    classDef ai fill:#ede4ff,stroke:#7c3aed,color:#3b0764
    classDef code fill:#e0ecff,stroke:#2563eb,color:#1e3a8a
    classDef codeCheck fill:#e0ecff,stroke:#1d4ed8,color:#1e3a8a,stroke-width:3px
    classDef human fill:#fff1d6,stroke:#d97706,color:#78350f
    classDef humanCheck fill:#fff1d6,stroke:#b45309,color:#78350f,stroke-width:3px
    classDef carrier fill:#f8fafc,stroke:#64748b,color:#334155,stroke-dasharray:4 3
    classDef legendCheck fill:#ffffff,stroke:#334155,color:#334155,stroke-width:3px

    class T input
    class E,L1 ai
    class B,API,BOT,EM,L2 code
    class TC,SC codeCheck
    class CH,L3 human
    class R humanCheck
    class ACME,BEACON,NW carrier
    class L4 legendCheck

    linkStyle 6 stroke:#dc2626,stroke-width:2px,stroke-dasharray:5 5
    linkStyle 7 stroke:#d97706,stroke-width:2px,stroke-dasharray:5 5
    style CANVAS fill:#ffffff,stroke:#ffffff
    style LEGEND fill:#ffffff,stroke:#e2e8f0
```

AI touches the data once, at the start. Everything after it is code proving something or a human deciding.

## Pipeline validation

The model's output is treated as a claim, not an answer. A **checkpoint** flags what code can't prove; a **gate** stops anything moving on until it passes.

| Step | Who | Type | What it does |
| --- | --- | --- | --- |
| Extract fields | AI | | Pulls each field's value and the exact quote it came from. Never trusted on its own |
| Transcript check | Code | Checkpoint | Quote exists in the transcript, value appears in the quote, valid format, no conflicting mentions |
| Broker review | Human | Gate | Approves, edits or fills every field before anything is built |
| Schema check | Code | Gate | Every field present with the right type and format before anything reaches a carrier |

Code proves a value wasn't invented. The broker confirms it's right. The schema guarantees every carrier gets the same well-formed record.

## Install and run

Requires Ruby 4.0, Rails 8 and [Ollama](https://ollama.com) with `granite4.2:8b`. Ollama is optional: without it, the sample transcripts use built-in fixture extractions.

```sh
./install.sh     # one-time setup on a new Mac
./run.sh         # starts Ollama and the app at http://localhost:3000
bin/rails test   # offline; never calls Ollama
```

## Examples

Three sample transcripts are preloaded on the start page.

| Sample | What happens in review | Acme API | Beacon bot | Northwind email |
| --- | --- | --- | --- | --- |
| **Northgate Dental** (happy path) | Everything verifies except years in business | Quoted, $23,800 | Quoted, $23,800 | Sent |
| **Hudson Millwork** (AI caught) | Eight fields go to the broker: FEIN spoken as words, NAICS never given, revenue in words, headcount corrected mid-call, a second location's ZIP, "first of April next year", a spelled-out email, years in business | Referred (revenue over $5M) | Referred | Sent |
| **Lumen Analytics** (channels differ) | ZIP+4 fails the format check until the broker fixes it | Quoted, $8,700 | Failed: no cyber option on the portal | Sent |
