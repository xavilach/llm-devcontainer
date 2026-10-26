---
name: unslop
description: "Remove AI writing patterns from any prose. Run it on every markdown file written for humans or LLMs (specs, designs, tickets, READMEs, skills, AGENTS.md, PR text) before showing it. Use when the user says /unslop or asks to clean up writing."
---

# Unslop

Edit the text to remove the patterns below, keeping the meaning and the intended tone. Scan for each pattern, then rewrite. Do not add content.

## Content

- **-ing filler.** Cut "highlighting", "ensuring", "reflecting", "showcasing", "fostering", or expand with a real fact.
- **Vague sources.** "Experts say", "reports suggest". Name the source or delete the claim.
- **Generic endings.** "The future looks bright." State a concrete plan or fact, or stop.

## Words

- **AI vocabulary.** Replace crucial, delve, enhance, pivotal, showcase, tapestry, testament, underscore, vibrant, intricate, landscape (abstract), interplay, garner, enduring with plain words.
- **Fancy "is".** "Serves as", "stands as", "boasts", "features" become "is" or "has".
- **"Not just X, but Y."** Say the point directly.
- **Forced triples.** Use the natural number of items.
- **Synonym cycling.** Pick one name for a thing and keep it.
- **False ranges.** "From X to Y" where X and Y are not on a scale. List the items.
- **Plain words.** utilize and leverage become use. facilitate becomes help. numerous becomes many. "In order to" becomes "to". "Due to the fact that" becomes "because". Delete "it is important to note that".
- **Hedging.** "Could potentially possibly" becomes "may".
- **Abstract nouns.** Substrate, vector, nexus, paradigm, bedrock, north star, flywheel, "API surface", scaffolding as a metaphor. Use the concrete word.

## Style

- **No em dashes.** Also avoid en dashes and hyphens used as dashes. End the sentence or use a comma.
- **Colons** only before a list or an example, not as a mid-sentence connector.
- **Bold** only where it earns it. An inline header list whose bold label restates the line ("**Performance:** performance improved") becomes prose. A bold lead-in naming the item and followed by new detail is fine.
- **Headings** in sentence case. No decorative emojis. Straight quotes.

## Plain speech

- **Say what it does, not how it feels.** "SQL you can read" becomes "`.toSQL()` returns the exact string sent to the database". If you cannot restate a sentence as an instruction, a fact or a number, cut it. If it could appear unchanged in another project's docs, cut it.
- **One idea per sentence.** Split any sentence the reader must re-read.
- **Active voice.** Name the actor: "queries are validated" becomes "the compiler validates queries". Passive is fine when the actor is unknown or irrelevant.
- **Fewer adverbs.** "Runs quickly" becomes "is fast" or the number. An adverb propping up a weak verb means the verb is wrong.
- **No mannered prose.** Cut aphorisms, rhetorical fragments and personified code ("the plan holds it"). Write the literal phrase.
- **Do not over-compress.** Keep articles and verbs. "Parser rejects bad date → exit 2" becomes "The parser rejects a bad date, exits with code 2, and writes nothing."
- **No chatbot or flattery.** Cut "I hope this helps", "Great question", "Certainly".
