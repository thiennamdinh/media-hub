# media-hub example question results

Manual trigger run:

```text
./scripts/tick.sh
RSS:        ingested 0/2050 attempted records
Bluesky:    ingested 0/798 attempted records
Polymarket: ingested 79/79 attempted records
```

Notes: RSS/Bluesky records were already present and skipped by dedupe. Polymarket now uses event-level discovery plus explicit event watchlists, so it reports leading outcomes rather than long-tail outcomes inside huge multi-outcome markets.

## 1. Most important stories from the last 24 hours, grouped by topic/source type

- **Cybersecurity / AI security, RSS:** The Hacker News and federal feeds show AI-assisted attacks, malicious npm packages targeting Claude/OpenAI Codex users, PAN-OS exploitation, Gitea/Gogs vulnerabilities, botnet takedowns, and supply-chain attacks.
- **Government / federal cyber, RSS:** Federal News Network and FedScoop have AI executive order / cyber directive stories, EHR cyber performance gaps, CISA staffing/DHS contract review items, and federal cyber resilience commentary.
- **Politics / courts, Bluesky:** the strongest cross-source Bluesky story is the Democracy Docket item on the Supreme Court and Alabama racial gerrymandering, amplified by Chris Hayes, Heather Cox Richardson, and Marc Elias.
- **Prediction markets / macro-geopolitics:** Polymarket now surfaces active event leaders: 2028 presidential-election leaders, party-nomination leaders, US-Iran agreement timelines, Fed decision, California/LA elections, and short-horizon Bitcoin markets.
- **Geopolitics / Russia-Ukraine:** Russia/Ukraine appears in Bluesky and RSS via Russia-linked cyber activity, Ukraine battlefield/drone stories, and Russia/Putin commentary.

## 2. Links showing up across multiple sources, and who is amplifying them

Top exact-link overlaps:

1. **Democracy Docket: Supreme Court / Alabama racial gerrymander**
   - Sources: `bluesky-actor:chrislhayes.bsky.social`, `hcrichardson.bsky.social`, `marcelias.bsky.social`
   - URL: `https://www.democracydocket.com/news-alerts/supreme-court-greenlights-alabamas-racial-gerrymander-signaling-free-rein-for-states-to-discriminate`

2. **arXiv: Hashprice moderates electricity demand response of Bitcoin miners**
   - Sources: `arxiv-cs`, `arxiv-econ`, `arxiv-eess`
   - URL: `https://arxiv.org/abs/2606.00587`

3. **Status News: Scott Pelley / CBS / Bari Weiss**
   - Sources: `bluesky-actor:mollyjongfast.bsky.social`, `jamellebouie.net`
   - URL: `https://www.status.news/p/scott-pelley-fired-60-minutes-bari-weiss-nick-bilton`

4. **Research overlap noise:** many arXiv items appear in both `arxiv-cs` and `arxiv-eess`; useful for research discovery, noisy for general intelligence.

## 3. Cybersecurity items from the last week, ranked by novelty/attention

Most useful security hits:

- **OpenAI Codex authentication tokens stolen in `codexui-android` npm supply-chain attack** — The Hacker News.
- **Malicious npm package stole files from Claude AI user directory via GitHub** — The Hacker News.
- **ChatGPhish turns ChatGPT web summaries into a phishing surface** — The Hacker News.
- **PAN-OS GlobalProtect auth bypass CVE-2026-0257 under active exploitation** — The Hacker News.
- **Gitea private container images exposed without authentication** — The Hacker News.
- **Gogs RCE vulnerability lets authenticated users execute arbitrary code** — The Hacker News.
- **CERT-In recommends 12-hour patching for internet-facing flaws amid AI-assisted attacks** — The Hacker News.
- **AI executive order sets stage for new cybersecurity directives** — Federal News Network.
- **EHR modernization effort lacks cyber performance measures, GAO finds** — FedScoop.
- **CyberGym-E2E: benchmark for AI agents' end-to-end cybersecurity capabilities** — arXiv CS.

## 4. Polymarket probability moves since yesterday, and whether any map to news

The Polymarket feed is much better after event-level discovery. Top same-window movement signals now include:

- **Israel announces Lebanon ceasefire extension by June 7:** ~99.8%, one-day change about +0.753.
- **Bitcoin / June price path:** `BTC above $62k on June 4` around 75%, down about -0.284 by Polymarket's one-day field; June $60k dip around 64%, up about +0.33.
- **2026 NBA Champion:** Knicks around 53.5%, Spurs around 46.6%, large recent swing.
- **US/Iran agreement timelines:** July/August/June variants are active; August 31 around 51%, June 15 around 13%, and related agreement/ceasefire-extension markets moved modestly.
- **California governor / LA mayoral markets:** Becerra leads California governor around 73.8%; Karen Bass leads LA mayor around 68%.

Potential mapping to news: Israel/Lebanon and US/Iran markets are the most geopolitically relevant and should be watched against RSS/geopolitics feeds.

## 5. Bluesky security / AI / geopolitics discussion not yet in mainstream RSS

Bluesky remains politics/commentary-heavy rather than security-specialist-heavy. Current social-only signals:

- Heather Cox Richardson: AfD alignment with Russia.
- Rick Wilson: Russia/Putin succession and anti-Trump political analysis.
- Mehdi Hasan: CIA/whistleblower/Epstein/Trump/Israel/Russia podcast link.
- Jamelle Bouie: Russia battlefield losses / Ukraine commentary.
- Chris Hayes: concern about degraded Google answer quality / AI-search-adjacent behavior.

Security-specific Bluesky signal is still weak; add infosec researchers, incident responders, and security lists.

## 6. Stories with high social discussion but low traditional RSS coverage

Likely social-heavy stories:

- **Democracy Docket / Alabama racial gerrymander / Supreme Court** — three Bluesky sources and many mentions, no obvious RSS overlap in top exact-link results.
- **Scott Pelley / CBS / Bari Weiss / 60 Minutes** — amplified by Molly Jong-Fast and Jamelle Bouie.
- **Marc Elias / Democracy Docket links** — high repeated social amplification.
- **JoJoFromJerz / Rick Wilson Substack and YouTube links** — single-source-high social amplification, less cross-source confirmation.

Caveat: old pre-dedupe records still inflate some counts.

## 7. Noisy or low-value sources to remove/downweight

Candidates:

- **Broken RSS feeds:** Science Magazine News 403, ThinkProgress 403, The Blockchain 404, The NonProfit Times 404, OpenAI News 403.
- **High-volume/noisy:** `arxiv-cs` dominates volume and duplicates with `arxiv-eess`/`arxiv-econ`; filter by category/topic.
- **Low relevance:** nonprofit feeds may be less relevant unless intentionally tracked.
- **Bluesky politics actors:** current Bluesky config is politics-heavy; add security/AI/geopolitics specialists to rebalance.
- **Polymarket raw market discovery:** broad total-volume market discovery was weak; event-level leader extraction is better and should remain the default.

## 8. Under-covered topics and suggested sources

Under-covered relative to CS/cybersecurity R&D interests:

- **Vuln/threat intel:** CISA KEV, CISA alerts, Google TAG, Microsoft MSRC, Cloudflare blog, Project Zero, Trail of Bits, Bishop Fox, Wiz, Mandiant, Cisco Talos, Unit 42.
- **AI safety/security:** Anthropic research/news, METR, Apollo Research, Epoch AI, Redwood, NIST AI RMF updates, AI incident/security feeds.
- **Cyber policy/natsec:** Lawfare, War on the Rocks, CSIS, RAND, CFR cyber, Binding Hook, Net Politics.
- **Bluesky:** add infosec/security researchers/lists instead of relying mostly on political commentators.
- **Polymarket:** keep explicit event watchlists for AI, Taiwan/China, Russia/Ukraine, Iran, cyber incidents, elections, rates/macro, and major tech-regulation outcomes.

## 9. Clusters describing the same underlying event despite different URLs

Current exact/fuzzy clusters:

- **Supreme Court / Alabama racial gerrymander:** Democracy Docket URL shared by Chris Hayes, Heather Cox Richardson, Marc Elias.
- **Scott Pelley / CBS / Bari Weiss:** Status News URL shared by Molly Jong-Fast and Jamelle Bouie.
- **Bitcoin mining/electricity demand response:** same arXiv paper across CS/Econ/EESS.
- **Russia/Ukraine cyber/geopolitics:** Russia-linked GREYVIBE cyberattacks, Gamaredon targeting Ukraine, Ukraine drone/robotics stories, Foreign Policy Russia-Ukraine coverage.
- **AI/cyber supply-chain:** OpenAI Codex token theft, malicious Claude npm package, ChatGPhish, AI-assisted exploitation, exposed vibe-coded apps.
- **Prediction-market geopolitical cluster:** US/Iran agreement timeline markets and Israel/Lebanon ceasefire-extension market.

Next improvement: fuzzy title/entity clustering beyond exact `canonical_url`.

## 10. Morning intelligence brief

- **Cyber/AI security:** prioritize OpenAI Codex token theft, Claude npm package theft, ChatGPhish, Gitea/Gogs issues, PAN-OS exploitation, and CERT-In 12-hour patching guidance.
- **Federal cyber/policy:** AI executive order is driving new cybersecurity directives; EHR modernization has cyber performance gaps; DHS/CISA staffing and federal cyber resilience are active.
- **Geopolitics:** Russia/Ukraine remains prominent. Prediction markets add US/Iran and Israel/Lebanon ceasefire-extension as watch items.
- **Politics/social signal:** Democracy Docket's Alabama/Supreme Court story is the clearest cross-Bluesky amplification event.
- **Markets:** improved Polymarket output now shows leaders: JD Vance/Gavin Newsom/Marco Rubio lead 2028 presidential winner; Newsom leads Democratic nomination; J.D. Vance and Marco Rubio lead GOP nomination; Israel/Lebanon and Bitcoin markets had the largest near-term moves.
- **System health:** ingestion works; source quality still needs cleanup. Several feeds are broken, arXiv is too high-volume, and Bluesky is overly politics-heavy for security/AI discovery.
