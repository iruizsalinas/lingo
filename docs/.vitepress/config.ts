import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Lingo",
  description: "An Elixir library for interacting with the Discord API",
  cleanUrls: true,
  base: "/lingo/",

  themeConfig: {
    sidebar: [
      {
        text: "Getting Started",
        items: [
          { text: "Overview", link: "/" },
          { text: "Commands", link: "/commands" },
          { text: "Events", link: "/events" },
          { text: "Interactions", link: "/interactions" },
          { text: "API", link: "/api" },
          { text: "Cache", link: "/cache" },
        ],
      },
      {
        text: "Commands & Interactions",
        items: [
          { text: "Macros", link: "/commands/macros" },
          { text: "Context", link: "/commands/context" },
          { text: "Option Builders", link: "/commands/option-builders" },
          { text: "Message Components", link: "/commands/message-components" },
          { text: "Modal Components", link: "/commands/modal-components" },
        ],
      },
      {
        text: "API Reference",
        items: [
          { text: "Guilds, Members & Roles", link: "/api/guilds" },
          { text: "Channels & Messages", link: "/api/channels" },
          { text: "Interactions & Commands", link: "/api/interactions" },
          { text: "Other Resources", link: "/api/resources" },
        ],
      },
      {
        text: "Gateway",
        items: [
          { text: "Event List", link: "/gateway/event-list" },
          { text: "Intents", link: "/gateway/intents" },
          { text: "Sharding", link: "/gateway/sharding" },
          { text: "Presence", link: "/gateway/presence" },
          { text: "Commands", link: "/gateway/commands" },
        ],
      },
      {
        text: "Utilities",
        items: [
          { text: "Helpers", link: "/utilities/helpers" },
          { text: "Types", link: "/utilities/types" },
          { text: "Permissions", link: "/utilities/permissions" },
          { text: "CDN", link: "/utilities/cdn" },
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
