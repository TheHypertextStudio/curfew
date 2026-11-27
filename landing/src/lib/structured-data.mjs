// Search engines read the FAQ from this JSON-LD, so build it from the same
// <details> blocks visitors see. A separate copy would drift the first time
// someone edited an answer on the page.
function faqFromContent(content) {
  return [
    ...content.matchAll(/<details>\s*<summary>([\s\S]*?)<\/summary>([\s\S]*?)<\/details>/g),
  ].map(([, summary, answer]) => ({
    '@type': 'Question',
    name: plainText(summary.replace(/<svg[\s\S]*?<\/svg>/g, '')),
    acceptedAnswer: { '@type': 'Answer', text: plainText(answer) },
  }));
}

function plainText(html) {
  return html
    .replace(/<\/?(?:a|p|span|strong|em)(?:\s[^>]*)?>/g, '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * The home page's schema.org graph: the app itself and its FAQ.
 *
 * @param {object} options
 * @param {string} options.siteOrigin The deployed site origin, without a trailing slash.
 * @param {string} options.content The home page HTML that holds the visible FAQ.
 * @returns {string} JSON that is safe to place inside a script element.
 */
export function homeStructuredData({ siteOrigin, content }) {
  const graph = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'SoftwareApplication',
        name: 'Curfew',
        description:
          'A curfew for your Mac. Set your finish time and let Curfew enforce it, so work leaves room for the rest of your life.',
        applicationCategory: 'ProductivityApplication',
        operatingSystem: 'macOS 26',
        url: `${siteOrigin}/`,
        downloadUrl: `${siteOrigin}/download`,
        softwareHelp: { '@type': 'CreativeWork', url: `${siteOrigin}/support` },
        license: 'https://opensource.org/license/mit',
        isAccessibleForFree: true,
        screenshot: `${siteOrigin}/site-assets/design/assets/lockout-dark.png`,
        publisher: {
          '@type': 'Organization',
          name: 'Hypertext Studio',
          url: 'https://hypertext.studio',
        },
        // Curfew Plus is not for sale yet, so the free app is the only offer.
        offers: [{ '@type': 'Offer', price: '0', priceCurrency: 'USD' }],
      },
      { '@type': 'FAQPage', mainEntity: faqFromContent(content) },
    ],
  };
  return JSON.stringify(graph).replaceAll('<', '\\u003c');
}
