#!/usr/bin/env node
// Automated test runner using RCON for AutoGhostBuilder
// Launches Factorio as a server with RCON, executes tests, reports results

const { spawn, execSync } = require('child_process');
const { Rcon } = require('rcon-client');
const fs = require('fs');
const path = require('path');

// Configuration
const CONFIG_FILE = path.join(__dirname, '..', '..', '.local-config.json');
const config = fs.existsSync(CONFIG_FILE) ? JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) : {};
const FACTORIO_PATH = process.env.FACTORIO_PATH || config.factorio || 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Factorio\\bin\\x64\\factorio.exe';
const MOD_SOURCE_DIR = path.resolve(__dirname, '..', '..');
const TEMP_DIR = path.join(require('os').tmpdir(), 'factorio-test');
const TEST_MODS_DIR = path.join(TEMP_DIR, 'mods');
const TEST_SAVE = path.join(TEMP_DIR, 'test-save.zip');
const LOG_FILE = path.join(MOD_SOURCE_DIR, '.test-output.log');
const SERVER_SETTINGS = path.join(__dirname, 'server-settings.json');
const RCON_SETTINGS = path.join(__dirname, 'rcon-settings.json');

// Load RCON config
const rconConfig = JSON.parse(fs.readFileSync(RCON_SETTINGS, 'utf8'));
const RCON_PORT = rconConfig.port;
const RCON_PASSWORD = rconConfig.password;

// Ensure directories exist
if (!fs.existsSync(TEST_MODS_DIR)) {
    fs.mkdirSync(TEST_MODS_DIR, { recursive: true });
}

function killExistingFactorio() {
    try {
        execSync('taskkill /F /IM factorio.exe', { stdio: 'ignore' });
        return new Promise(resolve => setTimeout(resolve, 1000));
    } catch (e) {
        return Promise.resolve();
    }
}

console.log('AutoGhostBuilder Tests\n');

// Clear log file
if (fs.existsSync(LOG_FILE)) {
    fs.unlinkSync(LOG_FILE);
}

// Check if Factorio exists
if (!fs.existsSync(FACTORIO_PATH)) {
    console.error('❌ Factorio not found at:', FACTORIO_PATH);
    console.error('Set FACTORIO_PATH environment variable');
    process.exit(1);
}

// Create mod structure with symlink
function setupModDirectory() {
    const modLinkPath = path.join(TEST_MODS_DIR, 'AutoGhostBuilder');
    const modListPath = path.join(TEST_MODS_DIR, 'mod-list.json');

    // Remove old symlink if exists
    try {
        if (fs.existsSync(modLinkPath)) {
            fs.rmSync(modLinkPath, { recursive: true, force: true });
        }
    } catch (e) {}

    // Create junction/symlink to mod directory
    fs.symlinkSync(MOD_SOURCE_DIR, modLinkPath, 'junction');

    // Create mod-list.json
    const modList = {
        mods: [
            { name: 'base', enabled: true },
            { name: 'AutoGhostBuilder', enabled: true }
        ]
    };
    fs.writeFileSync(modListPath, JSON.stringify(modList, null, 2));
}

function createTestSave() {
    setupModDirectory();

    if (fs.existsSync(TEST_SAVE)) {
        fs.unlinkSync(TEST_SAVE);
    }

    const TEMPLATE_SAVE = path.join(__dirname, 'test-ghost-auto-builder.zip');
    if (!fs.existsSync(TEMPLATE_SAVE)) {
        throw new Error(`Template save not found: ${TEMPLATE_SAVE}`);
    }

    fs.copyFileSync(TEMPLATE_SAVE, TEST_SAVE);
}

function startServer() {
    console.log('Starting Factorio server...');

    return new Promise((resolve, reject) => {
        const command = [
            `"${FACTORIO_PATH}"`,
            '--start-server', `"${TEST_SAVE}"`,
            '--mod-directory', `"${TEST_MODS_DIR}"`,
            '--server-settings', `"${SERVER_SETTINGS}"`,
            '--rcon-port', RCON_PORT.toString(),
            '--rcon-password', RCON_PASSWORD,
            '--disable-audio'
        ].join(' ');

        const serverProc = spawn(command, [], {
            stdio: 'pipe',
            shell: true,
            windowsHide: true
        });

        let output = '';
        let ready = false;

        serverProc.stdout.on('data', (data) => {
            const text = data.toString();
            output += text;

            // Log server output to file for debugging
            fs.appendFileSync(LOG_FILE, text);

            // Check if server is ready
            if (text.includes('Hosting multiplayer game') || text.includes('changing state from(CreatingGame) to(InGame)')) {
                ready = true;
                resolve({ proc: serverProc, output });
            }
        });

        serverProc.stderr.on('data', (data) => {
            output += data.toString();
        });

        serverProc.on('error', reject);

        serverProc.on('close', (code) => {
            if (!ready) {
                reject(new Error('Server closed before becoming ready'));
            }
        });

        // Timeout after 30 seconds
        setTimeout(() => {
            if (!ready) {
                serverProc.kill();
                fs.writeFileSync(LOG_FILE, output);
                reject(new Error('Server startup timeout'));
            }
        }, 30000);
    });
}

// Extract and print test output line (only failures)
function printTestLine(line) {
    // Match failed test lines: "✗ test name"
    const failMatch = line.match(/test-harness\.lua:\d+:\s*✗\s*(.+)/);
    if (failMatch) {
        console.log(`  \x1b[31m✗ ${failMatch[1]}\x1b[0m`);
        return true;
    }

    // Match error detail lines (indented with 2 spaces after test name)
    const errorDetailMatch = line.match(/test-harness\.lua:\d+:\s{2,}(.+)/);
    if (errorDetailMatch) {
        let errorMsg = errorDetailMatch[1];
        const msgMatch = errorMsg.match(/__\w+__\/.*?:\d+:\s*(.+)/);
        if (msgMatch) {
            errorMsg = msgMatch[1];
        }
        console.log(`    \x1b[31m${errorMsg}\x1b[0m`);
        return true;
    }

    // Match summary line
    const summaryMatch = line.match(/Tests:\s*(\d+)\s*passed,\s*(\d+)\s*failed,\s*(\d+)\s*total/);
    if (summaryMatch) {
        const passed = summaryMatch[1];
        const failed = summaryMatch[2];
        const total = summaryMatch[3];
        if (failed === '0') {
            console.log(`\x1b[32m${passed} passed\x1b[0m, 0 failed, ${total} total`);
        } else {
            console.log(`\n${passed} passed, \x1b[31m${failed} failed\x1b[0m, ${total} total`);
        }
        return true;
    }

    return false;
}

// Execute tests via RCON
async function executeTests(serverProc) {

    let rcon;
    let fullOutput = '';

    // Capture ongoing server output and print test results
    const outputHandler = (data) => {
        const text = data.toString();
        fullOutput += text;

        // Print test output lines in real-time
        const lines = text.split('\n');
        for (const line of lines) {
            printTestLine(line);
        }
    };
    serverProc.stdout.on('data', outputHandler);
    serverProc.stderr.on('data', outputHandler);

    try {
        await new Promise(resolve => setTimeout(resolve, 5000));

        rcon = await Rcon.connect({
            host: 'localhost',
            port: RCON_PORT,
            password: RCON_PASSWORD,
            timeout: 10000
        });

        console.log('Running tests...');

        // Execute test command
        // Note: Factorio requires sending the command TWICE
        // First time shows achievement warning, second time actually executes
        try {
            await rcon.send('/silent-command remote.call("test_runner", "run_all_tests")');
            await new Promise(resolve => setTimeout(resolve, 500));
            await rcon.send('/silent-command remote.call("test_runner", "run_all_tests")');
        } catch (err) {
            console.error('❌ RCON command error:', err.message);
            throw err;
        }

        // Wait for tests to complete
        await new Promise(resolve => setTimeout(resolve, 2000));

        return parseTestResults(fullOutput);

    } finally {
        if (rcon) {
            try {
                await rcon.end();
            } catch (e) {
                // Ignore RCON close errors
            }
        }

        if (serverProc && !serverProc.killed) {
            serverProc.kill('SIGTERM');
            await new Promise(resolve => setTimeout(resolve, 2000));
            if (!serverProc.killed) {
                serverProc.kill('SIGKILL');
            }
        }

        try {
            execSync('taskkill /F /IM factorio.exe', { stdio: 'ignore' });
        } catch (e) {}

        await new Promise(resolve => setTimeout(resolve, 500));
    }
}

// Parse test results from output
function parseTestResults(output) {
    const results = {
        passed: 0,
        failed: 0,
        total: 0
    };

    // Look for test result line
    const summaryMatch = output.match(/Tests:\s*(\d+)\s*passed,\s*(\d+)\s*failed,\s*(\d+)\s*total/i);
    if (summaryMatch) {
        results.passed = parseInt(summaryMatch[1], 10);
        results.failed = parseInt(summaryMatch[2], 10);
        results.total = parseInt(summaryMatch[3], 10);
    }

    return results;
}

// Main execution
async function main() {
    try {
        await killExistingFactorio();
        await createTestSave();

        const { proc: serverProc } = await startServer();

        const results = await executeTests(serverProc);

        if (results.failed > 0) {
            process.exit(1);
        } else if (results.passed > 0) {
            process.exit(0);
        } else {
            console.log('\x1b[33mNo tests found\x1b[0m');
            process.exit(1);
        }

    } catch (error) {
        console.error('\n❌ Test runner error:', error.message);
        process.exit(1);
    }
}

main();
