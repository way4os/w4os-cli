<?php

/**
 * What the commands that act on this machine ask of the engine (run by the scripts of libexec/, not by hand):
 *
 *   run.php status
 *   run.php ports [instance...] [--publish|--ufw] [--private-address ADDRESS]
 *   run.php start [--robust] [target...]
 *   run.php stop|restart [--robust] [now] [target...]
 *   run.php console <instance>
 *   run.php install-dotnet [-y] [MAJOR]
 *   run.php module enable|disable NAME
 *
 * The engine says what it does on the error output, the answer is on the standard output. The status is 0 for a success, 1 for a
 * problem, 2 for a command that is not understood.
 */

declare(strict_types=1);

ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

use W4OS\Engine\Console\RestConsole;
use W4OS\Engine\Exceptions\InstanceFailed;
use W4OS\Engine\OpenSim;
use W4OS\Engine\Provisioning\UiInterface;
use W4OS\Engine\Runtime\DotnetInstaller;
use W4OS\Engine\Runtime\PendingReporterInterface;
use W4OS\Engine\Runtime\Status;
use OpenSimCli\Commands;

foreach ([__DIR__ . '/../../vendor/autoload.php', __DIR__ . '/../../../../autoload.php'] as $autoload) {
    if (is_file($autoload)) {
        require $autoload;

        break;
    }
}
if (!class_exists(OpenSim::class)) {
    fwrite(STDERR, "opensim: the engine is not installed (composer install)\n");
    exit(2);
}

/** What the engine says, on the error output as `opensim: <message>`; the details with DEBUG=yes, the errors only with QUIET=yes. */
final class CliReporter implements PendingReporterInterface
{
    private bool $pending = false;

    public function __construct(private readonly bool $debug = false, private readonly bool $quiet = false) {}

    public function info(string $message): void
    {
        $this->quiet || fwrite(STDERR, "opensim: $message\n");
    }

    public function error(string $message): void
    {
        fwrite(STDERR, "opensim: error: $message\n");
    }

    public function debug(string $message): void
    {
        $this->debug && fwrite(STDERR, "opensim: $message\n");
    }

    public function step(string $text): void
    {
        if ($this->quiet) {
            return;
        }
        fwrite(STDERR, ($this->pending ? "\r\033[K" : '') . "opensim: $text\n");
        $this->pending = false;
    }

    /** What the wait is on, on one line a terminal replaces with the next. */
    public function pending(string $text): void
    {
        if (!$this->quiet && stream_isatty(STDERR)) {
            fwrite(STDERR, "\r\033[Kopensim: $text");
            $this->pending = true;
        }
    }

    public function stepEnd(): void {}

    public function isTerminal(): bool
    {
        return stream_isatty(STDERR);
    }
}

/** No questions: the notes go to the standard output, the problems to the error output, every question gets its default. */
final class StdUi implements UiInterface
{
    public function intro(string $title): void {}

    public function note(string $message): void
    {
        fwrite(STDOUT, "$message\n");
    }

    public function entity(string $name): string
    {
        return $name;
    }

    public function warn(string $message): void
    {
        fwrite(STDERR, "$message\n");
    }

    public function error(string $message): void
    {
        fwrite(STDERR, "$message\n");
    }

    public function outro(string $message): void {}

    public function choose(string $label, array $options, ?string $default = null, ?string $hint = null): string
    {
        return $default ?? (string) array_key_first($options);
    }

    public function checklist(string $label, array $options, array $defaults = [], ?string $hint = null): array
    {
        return $defaults;
    }

    public function text(string $label, string $default = '', ?\Closure $validate = null, ?string $hint = null): string
    {
        return $default;
    }

    public function secret(string $label, ?\Closure $validate = null, ?string $hint = null): string
    {
        return '';
    }

    public function form(array $fields, string $title = ''): array
    {
        return [];
    }

    public function confirm(string $label, bool $default = true): bool
    {
        return $default;
    }

    public function spin(\Closure $callback, string $message): mixed
    {
        return $callback();
    }
}

/**
 * The table of the instances, then the summary line, then the Robusts whose grid info the viewers refuse, the instances on a .NET
 * major their core does not target, and the modules enabled that a simulator does not set up (kept off).
 *
 * @param list<string> $modules the modules enabled
 * @param ?\W4OS\Engine\Runtime\RuntimeProbe $probe tells the .NET major each instance runs on (none: not told)
 */
function render(Status $status, array $modules = [], ?\W4OS\Engine\Runtime\RuntimeProbe $probe = null, string $account = ''): string
{
    $rows = [['INSTANCE', 'TYPE', 'PID', 'USER', '%CPU', '%MEM', 'RSS', 'AVATARS']];
    // A Robust that runs but cannot read its database answers nothing that needs it: it is up, not working
    $withoutDatabase = $status->withoutDatabase();
    // A simulator whose process runs but does not answer is hung, or still loading: it is up, not working
    $unresponsive = $status->unresponsive();
    // The avatars in world, never a NPC: unknown where the databases of a grid cannot be read
    $avatars = $status->avatars(null, $withoutDatabase);
    foreach ($status->instances as $item) {
        $p = $item->process();
        $rows[] =
            $p === null
                ? [$item->name(), $item->type(), '[down]']
                : [
                    $item->name(),
                    $item->type(),
                    (string) $p->pid,
                    $p->user,
                    sprintf('%.1f', $p->cpu),
                    sprintf('%.1f', $p->memory),
                    (string) $p->rss,
                    (string) ($avatars['instances'][$item->name()] ?? '?') . (in_array($item->name(), $withoutDatabase, true) ? '  [no database]' : '')
                        . (in_array($item->name(), $unresponsive, true) ? '  [not answering]' : ''),
                ];
    }
    $widths = [];
    foreach ($rows as $row) {
        foreach ($row as $i => $cell) {
            $widths[$i] = max($widths[$i] ?? 0, strlen($cell));
        }
    }
    $text = '';
    foreach ($rows as $row) {
        $cells = [];
        foreach ($row as $i => $cell) {
            $cells[] = $i === count($row) - 1 ? $cell : str_pad($cell, $widths[$i] + 2);
        }
        $text .= implode('', $cells) . "\n";
    }
    $t = $status->totals();
    $line = $status->up() . ' up' . ($status->down() > 0 ? ', ' . $status->down() . ' down' : '')
        . ($withoutDatabase === [] ? '' : ', ' . count($withoutDatabase) . ' without its database (' . implode(', ', $withoutDatabase) . ')')
        . ($unresponsive === [] ? '' : ', ' . count($unresponsive) . ' not answering (' . implode(', ', $unresponsive) . ')');

    $known = array_filter($avatars['grids'], static fn(?int $count): bool => $count !== null);
    $unknown = array_keys(array_diff_key($avatars['grids'], $known));
    $count = array_sum($known);
    $people = $avatars['grids'] !== [] && $known === []
        ? 'avatars unknown'
        : $count . ($count === 1 ? ' avatar' : ' avatars') . ($unknown === [] ? '' : ' (unknown for ' . implode(', ', $unknown) . ')');

    $text .= sprintf("%s - %s - cpu %.1f%% - mem %.1f%% - rss %d\n", $line, $people, $t['cpu'], $t['memory'], $t['rss']);
    foreach ($status->brokenGridInfo() as $name => $broken) {
        $text .= "$name answers get_grid_info with what the viewers refuse ({$broken['defect']}): OpenSim's grid info cannot send non-ASCII characters."
            . " Fix: opensim settings $name grid --set gridName=" . escapeshellarg($broken['gridName']) . ", then opensim restart $name\n";
    }
    foreach ($probe === null ? [] : $status->wrongRuntimes($probe) as $name => $runtime) {
        $text .= "$name runs on .NET {$runtime['running']}, its core targets .NET {$runtime['target']}: its asset cache keeps nothing (grey skins)."
            . " Fix: sudo opensim install-dotnet {$runtime['target']}, then opensim restart $name\n";
    }
    foreach ($status->unconfigured($modules) as $module => $names) {
        $text .= "$module is installed but not configured, off for: " . implode(', ', $names)
            . (strtolower($module) === 'gloebit' ? ' (set gloebitKey and gloebitSecret: opensim settings GRID economy)' : '') . "\n";
    }

    return $text;
}

/** 1 when an instance failed (one still loading did not), else 0. */
function outcome(array $results): int
{
    foreach ($results as $result) {
        if ($result instanceof InstanceFailed) {
            return 1;
        }
    }

    return 0;
}

$args = array_slice($argv, 1);
$command = array_shift($args) ?? '';
// The user the instances run as, empty when the install has none (the commands then run as whoever calls them)
if ($command === 'system-user') {
    echo \W4OS\Engine\Config\Layout::resolve()->systemUser(), "\n";
    exit(0);
}
// A grid named comes with its simulators, its Robust alone with --robust (--simulators, of before, says the default)
$simulators = !in_array('--robust', $args, true);
$words = array_values(array_filter($args, static fn(string $a): bool => $a === '' || $a[0] !== '-'));
$engine = OpenSim::environment(
    new CliReporter(
        in_array(strtolower((string) getenv('DEBUG')), ['yes', 'true', '1'], true),
        in_array(strtolower((string) getenv('QUIET')), ['yes', 'true', '1'], true),
    ),
);
require_once __DIR__ . '/commands.php';
require_once __DIR__ . '/BanPlan.php';
$now = ($words[0] ?? '') === 'now';
$targets = $now ? array_slice($words, 1) : $words;

switch ($command) {
    case 'ports':
        require __DIR__ . '/ports.php';
        exit(showPorts($engine, $args));
    case 'status':
        echo render(OpenSim::status($engine), $engine->layout->enabledModules(), $engine->probe, $engine->layout->systemUser());
        exit(0);
    case 'start':
        exit(outcome(OpenSim::start($words ?: null, $engine, $simulators)));
    case 'stop':
        exit(outcome(OpenSim::stop($targets ?: null, $now, $engine, $simulators)));
    case 'restart':
        exit(outcome(OpenSim::restart($targets ?: null, $now, $engine, $simulators)));
    case 'enable':
    case 'disable':
        exit(Commands::toggle($command, $engine, $args));
    case 'web':
        exit(Commands::web($engine, $args));
    case 'next':
        exit(Commands::next($engine, $args));
    case 'save':
    case 'load':
        exit(Commands::archives($command, $engine, $args));
    case 'backup':
        exit(Commands::backup($engine, $args));
    case 'ban':
        exit(Commands::ban($engine, $args));
    case 'api-key':
        exit(Commands::apiKey($engine, $args));
    case 'rest':
        exit(Commands::rest($args, $engine));
    case 'oar':
        exit(Commands::oar($args));
    case 'console':
        $name = $words[0] ?? '';
        $instance = $name === '' ? null : OpenSim::instance($engine, $name);
        if ($instance === null) {
            $engine->reporter->error(
                $name === '' ? 'usage: opensim console <instance>' : "no ini file found for $name",
            );
            exit(1);
        }
        $screen = $engine->consoles->screen($instance->name());
        if ($screen->exists()) {
            $engine->reporter->info("console of {$instance->name()}, Ctrl-A D to leave it running");
            exit($screen->attach());
        }
        // The remote console: a prompt, every line typed goes to it
        $console = $instance->console();
        $session = $console instanceof RestConsole ? $console->session() : null;
        if ($session === null) {
            $engine->reporter->error("{$instance->name()} is not running");
            exit(1);
        }
        $engine->reporter->info("Connection to {$instance->name()}, Ctrl-D to exit the console safely");
        while (true) {
            echo $session->prompt !== '' ? $session->prompt : '> ';
            $line = fgets(STDIN);
            if ($line === false) {
                echo "\n";
                break;
            }
            $result = $session->command(rtrim($line, "\r\n"), RestConsole::WAIT);
            foreach ($result['lines'] as $text) {
                echo $text, "\n";
            }
            if ($result['closed']) {
                break;
            }
        }
        $session->close();
        exit(0);
    case 'module':
        // A module of the install, added to EnabledModules of w4os.conf or taken out of it, the others kept
        [$action, $name] = $words + ['', ''];
        if (count($words) !== 2 || !in_array($action, ['enable', 'disable'], true) || preg_match('/^[a-z0-9][a-z0-9_-]*$/i', $name) !== 1) {
            fwrite(STDERR, "usage: opensim module enable|disable NAME\n");
            exit(2);
        }
        $conf = (string) (getenv('OPENSIM_CONF') ?: \W4OS\Engine\Config\Layout::systemFile());
        if (!is_file($conf)) {
            fwrite(STDERR, "opensim: $conf is not there: the install has no modules to change\n");
            exit(1);
        }
        $on = $action === 'enable';
        $changed = (new \W4OS\Engine\Config\PackagedProfiles($conf))->enableModule($name, $on);
        echo $changed
            ? 'Module ' . strtolower($name) . ($on ? ' enabled' : ' disabled') . " for the install ($conf): the simulators take it at their next start (opensim restart)\n"
            : 'Module ' . strtolower($name) . ($on ? ' was enabled already' : ' was not enabled') . "\n";
        exit(0);
    case 'install-dotnet':
        if (count($words) > 1 || (isset($words[0]) && !ctype_digit($words[0]))) {
            fwrite(STDERR, "usage: opensim install-dotnet [-y] [MAJOR]\n");
            exit(2);
        }
        // The major given, else the ones the cores installed target: each core runs on its own, never a newer one
        $majors = isset($words[0]) ? [(int) $words[0]] : \W4OS\Engine\Runtime\Core::dotnetMajors(\W4OS\Engine\Config\Layout::resolve()->coreRoot());
        if ($majors === []) {
            echo "No .NET core installed: nothing to install (opensim install-dotnet MAJOR installs a runtime)\n";
            exit(0);
        }
        // Every question gets its default: the command asks nothing
        $installer = new DotnetInstaller(new StdUi());
        foreach ($majors as $major) {
            $installer->install($major) || exit(1);
        }
        exit(0);
}
fwrite(STDERR, "opensim: unknown command $command\n");
exit(2);
