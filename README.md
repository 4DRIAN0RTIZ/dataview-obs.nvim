# dataview-obs.nvim

Execute [Obsidian Dataview](https://github.com/blacksmithgu/obsidian-dataview) queries directly in Neovim. Renders results as virtual text inline and in floating windows , no Obsidian app required.

Works standalone with any markdown vault, and auto-detects the vault when [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) is installed.

## Features

- Renders ` ```dataview ` code blocks as virtual text (non-destructive)
- Interactive query float via `:DataviewQuery`
- Navigate results via `:DataviewLinks` , Telescope/`vim.ui.select` picker of all `[[links]]` in rendered blocks
- DQL subset: `TABLE`, `LIST`, `TASK`, `FROM`, `WHERE`, `SORT`, `LIMIT`
- Shortest unambiguous `file.link` (same behavior as Obsidian)
- Extensible: register custom functions and renderers in Lua

## Installation

### lazy.nvim (with obsidian.nvim , vault auto-detected)

```lua
{
    "4DRIAN0RTIZ/dataview-obs.nvim",
    ft = "markdown",
    dependencies = { "obsidian-nvim/obsidian.nvim" },
    config = function()
        require("dataview").setup()
    end,
}
```

### lazy.nvim (standalone)

```lua
{
    "4DRIAN0RTIZ/dataview-obs.nvim",
    ft = "markdown",
    config = function()
        require("dataview").setup({
            vault = vim.fn.expand("~/path/to/your/vault"),
        })
    end,
}
```

## Configuration

```lua
require("dataview").setup({
    vault       = nil,        -- path to vault; auto-detected from obsidian.nvim if nil
    auto_render = true,       -- render dataview blocks on BufReadPost / BufWritePost
})
```

## Commands

| Command | Description |
| ------- | ----------- |
| `:DataviewQuery` | Open interactive query prompt → float result |
| `:DataviewRefresh` | Rebuild note index |
| `:DataviewRender` | Re-render dataview blocks in current buffer |
| `:DataviewLinks` | Telescope/select picker of all `[[links]]` from rendered results → open note |

## DQL Reference

### Query types

```
TABLE field1 [AS "alias"], field2, ...
LIST [field]
TASK
```

### Clauses

```
FROM ""                  -- all notes
FROM "folder"            -- notes inside folder/
FROM #tag                -- notes with tag

WHERE field = "value"
WHERE field != "value"
WHERE field > 3
WHERE contains(tags, "obsidian") AND estado = "activo"

SORT field ASC | DESC
LIMIT 10
```

### Virtual fields

| Field | Description |
| ----- | ----------- |
| `file.link` | Wiki link , shortest unambiguous form |
| `file.name` | Filename without extension |
| `file.path` | Relative path from vault root |
| `file.folder` | Parent folder relative to vault root |

### Examples

```dataview
TABLE estado, tecnologia, prioridad
FROM ""
WHERE tipo = "proyecto"
SORT prioridad ASC
```

```dataview
LIST FROM "Daily" SORT date DESC LIMIT 7
```

```dataview
TASK FROM "proyectos" WHERE estado != "done"
```

## Extension API

```lua
-- Custom DQL function: usable in WHERE clauses
require("dataview").register_function("is_overdue", function(note, args)
    local due = note.frontmatter[args[1]]
    return due ~= nil and due < os.date("%Y-%m-%d")
end)

-- Custom renderer for a query type
require("dataview").register_renderer("table", function(rows, fields)
    -- return string[] of lines
end)

-- Programmatic query
local rows, ast = require("dataview").query('LIST FROM "Daily" LIMIT 5')
```

## How it works

1. On setup, scans the vault and parses YAML frontmatter from all `.md` files into an in-memory index
2. On `BufReadPost` / `BufWritePost`, detects ` ```dataview ` blocks and executes the query
3. Results are injected as `virt_lines` extmarks , the actual file is never modified
4. Index refreshes automatically after `:DataviewRefresh` and re-renders all open vault buffers

## Requirements

- Neovim 0.9+
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) (optional , for vault auto-detection)

## License

MIT
