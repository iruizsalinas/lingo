import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Lingo",
  description: "An Elixir library for interacting with the Discord API",
  cleanUrls: true,
  base: "/lingo/",

  themeConfig: {
    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "Getting Started", link: "/" },
          { text: "Commands", link: "/commands" },
          { text: "Events", link: "/events" },
          { text: "Interactions", link: "/interactions" },
          { text: "REST API", link: "/api" },
          { text: "Cache", link: "/cache" },
          { text: "Deployment & Config", link: "/deployment" },
        ],
      },
      {
        text: "Commands & Interactions",
        items: [
          { text: "Macros", link: "/bot-dsl" },
          { text: "Context", link: "/context" },
          { text: "Option Builders", link: "/option-builders" },
          { text: "Components", link: "/components" },
        ],
      },
      {
        text: "API Functions",
        items: [
          { text: "Guilds, Members & Roles", link: "/api-guilds" },
          { text: "Channels & Messages", link: "/api-channels" },
          { text: "Interactions & Commands", link: "/api-interactions" },
          { text: "Other Resources", link: "/api-resources" },
        ],
      },
      {
        text: "Gateway",
        items: [
          { text: "Event List", link: "/event-list" },
          { text: "Intents", link: "/intents" },
          { text: "Gateway Functions", link: "/gateway" },
        ],
      },
      {
        text: "Utilities",
        items: [
          { text: "Helpers", link: "/helpers" },
          { text: "Types", link: "/types" },
          { text: "Permissions", link: "/permissions" },
          { text: "CDN", link: "/cdn" },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/iruizsalinas/lingo" },
    ],

    search: {
      provider: "local",
    },

    outline: "deep",
  },
});
