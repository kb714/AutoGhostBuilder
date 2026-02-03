#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.join(__dirname, '..');
const CONFIG_FILE = path.join(ROOT_DIR, '.local-config.json');
const MOD_NAME = 'AutoGhostBuilder';

function loadConfig() {
    if (!fs.existsSync(CONFIG_FILE)) {
        console.error('Config not found. Run: yarn setup');
        process.exit(1);
    }
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
}

function updateJsonFile(filePath, version) {
    const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    content.version = version;
    fs.writeFileSync(filePath, JSON.stringify(content, null, 2) + '\n');
}

function main() {
    const version = process.argv[2];
    if (!version) {
        console.error('Usage: yarn release <version>');
        console.error('Example: yarn release 0.3.1');
        process.exit(1);
    }

    const config = loadConfig();

    if (!config.sevenZip || !fs.existsSync(config.sevenZip)) {
        console.error(`7-Zip not found at: ${config.sevenZip}`);
        console.error('Run: yarn setup');
        process.exit(1);
    }

    const buildDir = `${MOD_NAME}_${version}`;
    const releaseDir = path.join(ROOT_DIR, 'release');
    const zipPath = path.join(releaseDir, `${buildDir}.zip`);

    console.log(`Building release for ${MOD_NAME} version ${version}\n`);

    // Update versions
    console.log('Updating version...');
    updateJsonFile(path.join(ROOT_DIR, 'info.json'), version);
    updateJsonFile(path.join(ROOT_DIR, 'package.json'), version);

    // Clean
    const buildPath = path.join(ROOT_DIR, buildDir);
    if (fs.existsSync(buildPath)) {
        fs.rmSync(buildPath, { recursive: true });
    }
    if (fs.existsSync(zipPath)) {
        fs.unlinkSync(zipPath);
    }

    // Create directories
    if (!fs.existsSync(releaseDir)) {
        fs.mkdirSync(releaseDir);
    }
    fs.mkdirSync(buildPath);

    // Copy files
    console.log('Copying files...');
    const filesToCopy = ['info.json', 'control.lua', 'data.lua', 'changelog.txt', 'thumbnail.png'];
    const dirsToCopy = ['locale', 'graphics', 'src'];

    for (const file of filesToCopy) {
        const src = path.join(ROOT_DIR, file);
        if (fs.existsSync(src)) {
            fs.copyFileSync(src, path.join(buildPath, file));
        }
    }

    for (const dir of dirsToCopy) {
        const src = path.join(ROOT_DIR, dir);
        if (fs.existsSync(src)) {
            fs.cpSync(src, path.join(buildPath, dir), { recursive: true });
        }
    }

    // Remove test files
    const testsDir = path.join(buildPath, 'src', 'tests');
    if (fs.existsSync(testsDir)) {
        fs.rmSync(testsDir, { recursive: true });
    }

    // Create zip
    console.log('Creating zip...');
    execSync(`"${config.sevenZip}" a -tzip "${zipPath}" "${buildPath}"`, {
        cwd: ROOT_DIR,
        stdio: 'inherit'
    });

    // Clean up
    fs.rmSync(buildPath, { recursive: true });

    console.log(`\n✅ Release created: release/${buildDir}.zip`);
}

main();
