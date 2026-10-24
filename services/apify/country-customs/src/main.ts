import { Actor } from "apify";
import { CheerioCrawler, Dataset } from "crawlee";

const CUSTOMS_URLS: Record<string, string> = {
  IN: "https://www.cbic.gov.in/",
  CN: "http://english.customs.gov.cn/",
  KR: "https://www.customs.go.kr/english/cm/cntnts/cntntsView.do?mi=8028&cntntsId=2724",
  GB: "https://www.gov.uk/hand-luggage-restrictions/liquids",
  IS: "https://www.mast.is/en/import-export",
};

await Actor.init();
const input = (await Actor.getInput<{ countries?: string[] }>()) ?? {};
const countries = input.countries ?? Object.keys(CUSTOMS_URLS);

const crawler = new CheerioCrawler({
  async requestHandler({ $, request }) {
    const country = request.userData.country as string;
    const text = $("body").text().replace(/\s+/g, " ").slice(0, 2000);
    await Dataset.pushData({
      scope: "country",
      country,
      subject: country,
      name: `${country} customs restrictions`,
      carryOn: "yes_with_limits",
      checked: "yes_with_limits",
      description: text.slice(0, 400),
      url: request.url,
      scrapedAt: new Date().toISOString().slice(0, 10),
      keywords: ["food", "meat", "liquid", "battery"],
      categories: ["food", "liquids", "electronics"],
    });
  },
});

await crawler.run(
  countries
    .filter((c) => CUSTOMS_URLS[c])
    .map((c) => ({ url: CUSTOMS_URLS[c]!, userData: { country: c } })),
);
await Actor.exit();
