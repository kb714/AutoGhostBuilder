-- src/tests/test-harness.lua
-- Test harness that runs tests inside Factorio

local GhostBuilder = require("src.core.ghost-builder")

local test_results = {
    passed = 0,
    failed = 0,
    total = 0
}

local assert_lib = {
    is_true = function(value, msg)
        if not value then
            error((msg or "Expected true") .. ", got " .. tostring(value))
        end
    end,

    is_false = function(value, msg)
        if value then
            error((msg or "Expected false") .. ", got " .. tostring(value))
        end
    end,

    is_nil = function(value, msg)
        if value ~= nil then
            error((msg or "Expected nil") .. ", got " .. tostring(value))
        end
    end,

    equals = function(expected, actual, msg)
        if expected ~= actual then
            error(string.format("%sExpected %s, got %s",
                msg and (msg .. ": ") or "",
                tostring(expected),
                tostring(actual)))
        end
    end
}

local function run_test(name, test_func)
    test_results.total = test_results.total + 1

    local success, err = pcall(test_func, assert_lib)

    if success then
        test_results.passed = test_results.passed + 1
        local msg = "✓ " .. name
        game.print("[color=green]" .. msg .. "[/color]")
        log(msg)
    elseif err and string.match(tostring(err), "SKIP:") then
        test_results.total = test_results.total - 1
        local msg = "⊘ " .. name .. " (skipped)"
        game.print("[color=yellow]" .. msg .. "[/color]")
        log(msg)
    else
        test_results.failed = test_results.failed + 1
        local msg = "✗ " .. name
        game.print("[color=red]" .. msg .. "[/color]")
        log(msg)

        -- Show detailed error with stack trace
        local err_msg = tostring(err)
        for line in err_msg:gmatch("[^\r\n]+") do
            game.print("[color=red]  " .. line .. "[/color]")
            log("  " .. line)
        end
    end
end

local core_tests = require("src.tests.core")
local item_requests_tests = require("src.tests.item-requests")
local compatibility_tests = require("src.tests.compatibility")

function run_all_tests()
    test_results.passed = 0
    test_results.failed = 0
    test_results.total = 0

    game.print("========================================")
    game.print("Running AutoGhostBuilder Tests")
    game.print("========================================")

    GhostBuilder.reset_state()

    game.print("\n[Core Logic & Ghost Building]")
    core_tests(run_test)

    game.print("\n[Item Requests & Upgrade Planner]")
    item_requests_tests(run_test)

    game.print("\n[Compatibility]")
    compatibility_tests(run_test)

    game.print("========================================")
    local summary = string.format("Tests: %d passed, %d failed, %d total",
        test_results.passed, test_results.failed, test_results.total)
    game.print(summary)
    log(summary)
    game.print("========================================")

    if test_results.failed > 0 then
        game.print("[color=red]TESTS FAILED[/color]")
        log("TESTS FAILED")
    else
        game.print("[color=green]ALL TESTS PASSED[/color]")
        log("ALL TESTS PASSED")
    end

    pcall(function()
        if game.write_file then
            game.write_file("test-results.txt", string.format("%d,%d,%d",
                test_results.passed, test_results.failed, test_results.total))
        end
    end)
end

if not remote.interfaces["test_runner"] then
    remote.add_interface("test_runner", {
        run_all_tests = function()
            run_all_tests()
            return {passed = test_results.passed, failed = test_results.failed, total = test_results.total}
        end
    })
end

return {
    run_all_tests = run_all_tests
}
