<?php

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
header('Content-Type: text/xml');

if ($path === '/StartSession/') {
    parse_str(file_get_contents('php://input'), $input);
    if (($input['USER'] ?? '') !== 'admin' || ($input['PASS'] ?? '') !== 'secret') {
        http_response_code(401);
        exit;
    }
    echo '<?xml version="1.0"?><ConsoleSession><SessionID>fixture-session</SessionID><Prompt>Region (Test) # </Prompt></ConsoleSession>';
} elseif ($path === '/SessionCommand/') {
    // The command typed, answered at the next reading: its echo, a line, the prompt
    parse_str(file_get_contents('php://input'), $input);
    file_put_contents(sys_get_temp_dir() . '/rest-console-fixture-' . getmypid(), (string) ($input['COMMAND'] ?? ''));
    echo '<?xml version="1.0"?><ClientInfo><Result>OK</Result></ClientInfo>';
} elseif (str_starts_with((string) $path, '/ReadResponses/')) {
    $file = sys_get_temp_dir() . '/rest-console-fixture-' . getmypid();
    $command = is_file($file) ? (string) file_get_contents($file) : '';
    is_file($file) && unlink($file);
    echo '<?xml version="1.0"?><ConsoleSession>';
    if ($command !== '') {
        echo '<Line Number="1" Input="true" Command="true">' . htmlspecialchars($command) . '</Line>';
        echo '<Line Number="2">answer to ' . htmlspecialchars($command) . '</Line>';
        echo '<Line Number="3" Prompt="true" Command="true">Region (Test) # </Line>';
    }
    echo '</ConsoleSession>';
} elseif ($path === '/CloseSession/') {
    echo '<?xml version="1.0"?><ConsoleSession><Result>OK</Result></ConsoleSession>';
} else {
    http_response_code(404);
}
