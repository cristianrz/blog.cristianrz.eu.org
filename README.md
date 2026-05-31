# Blog

A minimal static blog. HTML files are written by hand; the scripts handle
headers/footers, backups, and deployment.

## Directory structure

```
.
├── index.html
├── header.html        # Shared header; use %a%b%c as the page title placeholder
├── footer.html        # Shared footer
├── article/           # Article pages
├── page/              # Other pages (about, etc.)
├── blog.sh            # Create new pages
├── build.sh           # Rebuild all pages
└── deploy.sh          # Deploy to ~/public_html
```

## Workflow

### 1. Create a new page

```sh
./blog.sh new <category> <pagename>
# e.g.
./blog.sh new article my-first-post
./blog.sh new page about
```

This creates `<category>/<pagename>.html` with stub content wrapped in the
required `<!-- BEGIN MAIN CONTENT -->` / `<!-- END MAIN CONTENT -->` markers.

Edit the file and set a title via an `<h2>` tag — there should be exactly one.
Then add a link to it in `index.html` manually.

### 2. Build

```sh
./build.sh
```

Processes every `.html` file under `index.html`, `page/`, and `article/`.
For each file it:

- Extracts the `<h2>` text and injects it into `header.html` (replacing `%a%b%c`)
- Strips everything outside the `BEGIN`/`END MAIN CONTENT` markers
- Wraps the content with `header.html` and `footer.html`
- Saves the old file as `<file>.bak` before overwriting

Run this before every deployment.

### 3. Deploy

```sh
./deploy.sh
```

- Hard-resets the git working tree (`git reset HEAD --hard`), discarding any
  uncommitted changes
- Wipes `~/public_html` and copies all `.html` and `.xml` files from `.`,
  `article/`, and `page/` into it
- Sets permissions: files `0644`, directories `0755`

**Commit everything before deploying** — the hard reset will discard
uncommitted work.

## Notes

- `build.sh` creates `.bak` files alongside every processed page. These are
  safe to ignore or delete; they are not deployed.
- The `%a%b%c` placeholder in `header.html` is what gets replaced with the
  page title — don't change it without updating `build.sh`.
