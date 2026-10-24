import { Actor } from "apify";
import { CheerioCrawler, Dataset } from "crawlee";

await Actor.init();

const input = (await Actor.getInput<{
  startUrls?: { url: string }[];
  maxItems?: number;
}>()) ?? {};

const startUrls = input.startUrls?.length
  ? input.startUrls
  : [{ url: "https://www.tsa.gov/travel/security-screening/whatcanibring/all" }];
const maxItems = input.maxItems ?? 200;
let saved = 0;

const crawler = new CheerioCrawler({
  maxRequestsPerCrawl: maxItems + 50,
  async requestHandler({ $, request, enqueueLinks, log }) {
    const path = new URL(request.loadedUrl ?? request.url).pathname;
    if (path.includes("/items/")) {
      if (saved >= maxItems) return;
      const name = $("h1").first().text().trim() || $("title").text().trim();
      const body = $("article, .content, main").text().replace(/\s+/g, " ").trim();
      const carryOn = /carry-?on[^.]{0,40}(yes|no|ok)/i.exec(body)?.[1] ?? "unknown";
      const checked = /checked[^.]{0,40}(yes|no|ok)/i.exec(body)?.[1] ?? "unknown";
      await Dataset.pushData({
        name,
        carryOn: carryOn.toLowerCase(),
        checked: checked.toLowerCase(),
        description: body.slice(0, 500),
        url: request.loadedUrl ?? request.url,
        scrapedAt: new Date().toISOString().slice(0, 10),
      });
      saved += 1;
      log.info(`saved ${name}`);
      return;
    }

    await enqueueLinks({
      selector: 'a[href*="/travel/security-screening/whatcanibring/items/"]',
      label: "ITEM",
    });
  },
});

await crawler.run(startUrls);
await Actor.exit();
