# TinkerDesk

TinkerDesk is a clean-room native macOS workbench for running PHP inside a local Laravel application.

## Included in the first release

- Opens and validates a local Laravel project with installed Composer dependencies.
- Detects Homebrew or system PHP, with a manual PHP picker.
- Bundles PHPantom 0.11.1 for project-aware completion and automatic namespace imports.
- Opens each Laravel project in its own switchable tab.
- Highlights PHP with a Laravel documentation-inspired dark palette.
- Runs snippets in a fully booted Laravel console context.
- Captures printed output, returned values, PHP/Laravel versions, timing, and throwable details.
- Runs with `Command-R`, force-stops with `Esc`, and retains the editor contents after failures.
- Persists open project tabs, per-project snippets, and the PHP executable locally.

## Build

```
./Scripts/package-app.sh
```

Open `TinkerDesk.app` in the `dist` directory.

The generated app is ad-hoc signed for local development. Distribution to other Macs requires an Apple Developer ID signature and notarization.

PHPantom is bundled under its MIT license. Its binary and license live in `Vendor/PHPantom`; the packaged app places them in `Contents/Helpers` and `Contents/Resources`.

## License

TinkerDesk is available under the MIT License. Copyright © 2026 dkc.

## Snippet format

Write the body you would normally enter in `php artisan tinker`; the `<?php` tag is optional.
Press `Command-R` to run it. While it is running, press `Esc` to terminate the PHP process.

```php
return [
    'name' => config('app.name'),
    'users' => App\Models\User::query()->count(),
];
```
