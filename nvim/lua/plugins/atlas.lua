return {
  "emrearmagan/atlas.nvim",
  cmd = { "Atlas", "AtlasDiff" },
  keys = {
    { "<leader>ga", "<cmd>Atlas pulls<cr>", desc = "Atlas (Pull Requests)" },
  },
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    "MeanderingProgrammer/render-markdown.nvim",
    "sindrets/diffview.nvim",
  },
  ---@type AtlasConfig
  opts = {
    providers = {
      ---@type AtlasGitHubConfig
      github = {
        cache_ttl = 300,
      },
      ---@type AtlasGitLabConfig
      gitlab = {},
      ---@type AtlasBitbucketConfig
      bitbucket = {},
      ---@type AtlasJiraConfig
      jira = {},
    },

    pulls = {
      diff = {
        open_cmd = "DiffviewOpen",
      },

      ---@type AtlasGitHubPullsConfig
      github = {
        ---@type AtlasGitHubViewConfig[]
        views = {
          {
            name = "My PRs",
            key = "1",
            layout = "plain",
            search = "author:@me sort:updated-desc",
          },
          {
            name = "Team",
            key = "2",
            layout = "compact",
            search = "org:your-org sort:updated-desc",
          },
          {
            name = "Repo",
            key = "3",
            layout = "plain",
            search = "repo:your-org/your-repo",
          },
        },

        bookmarks = {
          key = "S",
          label = "Search",
          items = {
            ["Drafts"] = "is:pr is:draft author:@me",
            ["Recently merged"] = "is:pr is:merged author:@me sort:updated-desc",
            ["Review requested"] = "is:pr is:open review-requested:@me",
          },
        },
      },
    },

    issues = {
      ---@type AtlasGitHubIssuesConfig
      github = {
        ---@type AtlasGitHubIssuesViewConfig[]
        views = {
          {
            name = "Assigned",
            key = "1",
            layout = "plain",
            search = "assignee:@me is:open",
          },
          {
            name = "Created",
            key = "2",
            layout = "compact",
            search = "author:@me is:open",
          },
          {
            name = "Mentions",
            key = "3",
            layout = "plain",
            search = "mentions:@me is:open",
          },
        },

        bookmarks = {
          key = "S",
          label = "Search",
          items = {
            ["Bugs"] = "is:issue is:open label:bug",
            ["Recently closed"] = "is:issue is:closed author:@me sort:updated-desc",
          },
        },
      },
      ---@type AtlasJiraIssuesConfig
      jira = {},
      ---@type AtlasGitLabIssuesConfig
      gitlab = {},
    },
  },
}
