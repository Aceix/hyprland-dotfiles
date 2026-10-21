return {
  backend = "kitty", -- Kitty's terminal natively speaks the kitty graphics protocol
  processor = "magick_cli",
  integrations = {
    markdown = {
      enabled = true,
      clear_in_insert_mode = false,
      download_remote_images = true, -- Automatically pulls down online URL image pathways
      only_render_image_at_cursor = false,
    },
    neorg = { enabled = true },
  },
  max_width = 100,
  max_height = 12,
  max_width_window_percentage = math.huge,
  max_height_window_percentage = math.huge,
  window_overlap_clear_enabled = true, -- Cleans image artifacts when windows hide or move
}
