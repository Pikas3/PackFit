import { Actor } from "apify";
import { CheerioCrawler, Dataset } from "crawlee";

/** Hardcoded policy URLs — discovery is out of scope. */
const POLICY_URLS: Record<string, string> = {
  UA: "https://www.united.com/ual/en/us/fly/baggage/checked-bags.html",
  AA: "https://www.aa.com/i18n/travel-info/baggage/checked-baggage.jsp",
  AI: "https://www.airindia.com/in/en/book/baggage-information.html",
  EK: "https://www.emirates.com/us/english/before-you-fly/baggage/checked-baggage/",
  QR: "https://www.qatarairways.com/en/baggage/allowance.html",
};

await Actor.init();
const input = (await Actor.getInput<{ airlines?: string[] }>()) ?? {};
const airlines = input.airlines ?? Object.keys(POLICY_URLS);

const crawler = new CheerioCrawler({
  async requestHandler({ $, request }) {
    const airline = request.userData.airline as string;
    const text = $("body").text().replace(/\s+/g, " ").slice(0, 2000);
    const kg = /23\s*kg|50\s*lb/i.test(text) ? 23 : undefined;
    await Dataset.pushData({
      scope: "airline",
      airline,
      subject: airline,
      name: `${airline} checked baggage`,
      carryOn: "ok",
      checked: kg ? "yes_with_limits" : "unknown",
      description: text.slice(0, 400),
      url: request.url,
      limits: kg ? { maxKg: kg } : undefined,
      scrapedAt: new Date().toISOString().slice(0, 10),
    });
  },
});

await crawler.run(
  airlines
    .filter((a) => POLICY_URLS[a])
    .map((a) => ({ url: POLICY_URLS[a]!, userData: { airline: a } })),
);
await Actor.exit();
