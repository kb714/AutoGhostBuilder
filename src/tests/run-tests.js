#!/usr/bin/env node
// Automated test runner using RCON for AutoGhostBuilder
// Launches Factorio as a server with RCON, executes tests, reports results

const { spawn, execSync } = require('child_process');
const { Rcon } = require('rcon-client');
const fs = require('fs');
const path = require('path');

// Configuration
const FACTORIO_PATH = process.env.FACTORIO_PATH || 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Factorio\\bin\\x64\\factorio.exe';
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

// Kill any existing Factorio processes
function killExistingFactorio() {
    try {
        console.log('🧹 Cleaning up existing Factorio processes...');
        execSync('taskkill /F /IM factorio.exe', { stdio: 'ignore' });
        // Wait for process to fully terminate
        return new Promise(resolve => setTimeout(resolve, 1000));
    } catch (e) {
        // No factorio running, continue
        return Promise.resolve();
    }
}

console.log('🧪 AutoGhostBuilder Test Runner (RCON Mode)');
console.log('==========================================\n');

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

// Create a test save with player
function createTestSave() {
    console.log('📦 Creating test save file...');

    setupModDirectory();

    // Remove old save
    if (fs.existsSync(TEST_SAVE)) {
        fs.unlinkSync(TEST_SAVE);
    }

    // Use pre-made save with player instead of creating new one
    const TEMPLATE_SAVE = path.join(__dirname, 'test-ghost-auto-builder.zip');

    if (!fs.existsSync(TEMPLATE_SAVE)) {
        throw new Error(`Template save not found: ${TEMPLATE_SAVE}`);
    }

    console.log('📋 Copying template save with player...');
    fs.copyFileSync(TEMPLATE_SAVE, TEST_SAVE);
    console.log('✅ Test save created\n');
}

// Start Factorio server with RCON
function startServer() {
    console.log('🚀 Starting Factorio server with RCON...');

    return new Promise((resolve, reject) => {
        const serverArgs = [
            '--start-server', TEST_SAVE,
            '--mod-directory', TEST_MODS_DIR,
            '--server-settings', SERVER_SETTINGS,
            '--rcon-port', RCON_PORT.toString(),
            '--rcon-password', RCON_PASSWORD,
            '--disable-audio'
        ];

        const serverProc = spawn(`"${FACTORIO_PATH}"`, serverArgs, {
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

// Execute tests via RCON
async function executeTests(serverProc) {
    console.log('🔌 Connecting to server via RCON...\n');

    let rcon;
    let fullOutput = '';

    // Capture ongoing server output
    const outputHandler = (data) => {
        fullOutput += data.toString();
    };
    serverProc.stdout.on('data', outputHandler);
    serverProc.stderr.on('data', outputHandler);

    try {
        // Wait for server to be fully ready for RCON commands
        console.log('⏳ Waiting for server to fully initialize...');
        await new Promise(resolve => setTimeout(resolve, 5000));

        rcon = await Rcon.connect({
            host: 'localhost',
            port: RCON_PORT,
            password: RCON_PASSWORD,
            timeout: 10000  // 10 second timeout for RCON commands
        });

        console.log('✅ RCON connected');
        console.log('🧪 Running tests...\n');

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

        // Wait for tests to complete and output to be written
        await new Promise(resolve => setTimeout(resolve, 2000));

        console.log('📊 Test execution complete\n');

        // Read results from captured output
        const results = parseTestResults(fullOutput);

        return results;

    } finally {
        if (rcon) {
            try {
                await rcon.end();
            } catch (e) {
                // Ignore RCON close errors
            }
        }

        // Kill server forcefully
        console.log('🛑 Stopping Factorio server...');
        if (serverProc && !serverProc.killed) {
            serverProc.kill('SIGTERM');
            await new Promise(resolve => setTimeout(resolve, 2000));

            // Force kill if still running
            if (!serverProc.killed) {
                serverProc.kill('SIGKILL');
            }
        }

        // Extra cleanup: kill any remaining factorio processes
        try {
            execSync('taskkill /F /IM factorio.exe', { stdio: 'ignore' });
        } catch (e) {
            // Ignore if no process found
        }

        console.log('✅ Server stopped');
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

        console.log('================================');
        console.log('📊 Test Results');
        console.log('================================');
        console.log(`Passed: ${results.passed}`);
        console.log(`Failed: ${results.failed}`);
        console.log(`Total:  ${results.total}`);
        console.log('================================\n');

        if (results.failed > 0) {
            console.log('❌ TESTS FAILED');
            process.exit(1);
        } else if (results.passed > 0) {
            console.log('✅ ALL TESTS PASSED');
            process.exit(0);
        } else {
            console.log('⚠️  NO TESTS FOUND OR ERROR');
            process.exit(1);
        }

    } catch (error) {
        console.error('\n❌ Test runner error:', error.message);
        process.exit(1);
    }
}

main();
