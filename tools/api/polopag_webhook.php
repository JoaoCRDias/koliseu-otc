<?php
declare(strict_types=1);

/**
 * Polopag Webhook (GLOBAL) receiver.
 *
 * What this script does:
 * - Accepts POST JSON notifications from Polopag
 * - Optionally validates HMAC signature (POLOPAG_WEBHOOK_SECRET)
 * - Normalizes payment status
 * - Writes a local log for auditing
 * - Provides an integration point to credit coins in your site (MyAAC)
 *
 * Configure in your hosting env:
 * - POLOPAG_WEBHOOK_SECRET   (optional but recommended)
 * - POLOPAG_WEBHOOK_LOG      (optional; default: ./polopag_webhook.log)
 * - POLOPAG_DEBUG            (optional; "1" to include debug details)
 */

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function jsonResponse(array $payload, int $statusCode = 200): void
{
    http_response_code($statusCode);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function envStr(string $key, string $default = ''): string
{
    $value = getenv($key);
    if ($value === false) {
        return $default;
    }
    return trim((string)$value);
}

function pickNested(array $data, array $paths)
{
    foreach ($paths as $path) {
        $cursor = $data;
        $ok = true;
        foreach ($path as $segment) {
            if (!is_array($cursor) || !array_key_exists($segment, $cursor)) {
                $ok = false;
                break;
            }
            $cursor = $cursor[$segment];
        }
        if ($ok && $cursor !== null && $cursor !== '') {
            return $cursor;
        }
    }
    return null;
}

function appendWebhookLog(string $message, array $context = []): void
{
    $logPath = envStr('POLOPAG_WEBHOOK_LOG', __DIR__ . '/polopag_webhook.log');
    $line = sprintf(
        "[%s] %s %s\n",
        date('Y-m-d H:i:s'),
        $message,
        $context ? json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : ''
    );
    @file_put_contents($logPath, $line, FILE_APPEND);
}

function normalizePaymentStatus(string $status): string
{
    $s = strtolower(trim($status));
    if ($s === '') {
        return 'unknown';
    }

    $paid = ['paid', 'approved', 'success', 'completed', 'settled', 'confirmed'];
    $pending = ['pending', 'waiting', 'processing', 'created'];
    $failed = ['failed', 'canceled', 'cancelled', 'expired', 'refused', 'chargeback'];

    if (in_array($s, $paid, true)) {
        return 'paid';
    }
    if (in_array($s, $pending, true)) {
        return 'pending';
    }
    if (in_array($s, $failed, true)) {
        return 'failed';
    }
    return $s;
}

/**
 * TODO: Integrate with your MyAAC payment/coins system.
 * You should:
 * 1) Locate your payment by $reference (or provider transaction id)
 * 2) Ensure idempotency (do not credit twice)
 * 3) Credit account/character coins when status is "paid"
 * 4) Mark payment as processed
 */
function processPaidPayment(string $reference, string $providerTxId, float $amount, array $payload): void
{
    // Placeholder integration point.
    appendWebhookLog('PAID_RECEIVED', [
        'reference' => $reference,
        'provider_tx_id' => $providerTxId,
        'amount' => $amount
    ]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse([
        'ok' => false,
        'message' => 'Method not allowed.'
    ], 405);
}

$rawBody = file_get_contents('php://input');
if ($rawBody === false || trim($rawBody) === '') {
    jsonResponse([
        'ok' => false,
        'message' => 'Empty body.'
    ], 400);
}

$payload = json_decode($rawBody, true);
if (!is_array($payload)) {
    appendWebhookLog('INVALID_JSON', ['body' => substr($rawBody, 0, 1000)]);
    jsonResponse([
        'ok' => false,
        'message' => 'Invalid JSON body.'
    ], 400);
}

$debugEnabled = envStr('POLOPAG_DEBUG', '0') === '1';

// Optional signature validation (recommended).
$secret = envStr('POLOPAG_WEBHOOK_SECRET');
if ($secret !== '') {
    $receivedSignature = $_SERVER['HTTP_X_POLPAG_SIGNATURE'] ?? $_SERVER['HTTP_X_POLOPAG_SIGNATURE'] ?? '';
    if ($receivedSignature === '') {
        appendWebhookLog('SIGNATURE_MISSING');
        jsonResponse([
            'ok' => false,
            'message' => 'Missing webhook signature.'
        ], 401);
    }

    $computed = hash_hmac('sha256', $rawBody, $secret);
    if (!hash_equals($computed, trim($receivedSignature))) {
        appendWebhookLog('SIGNATURE_INVALID', ['received' => $receivedSignature]);
        jsonResponse([
            'ok' => false,
            'message' => 'Invalid webhook signature.'
        ], 401);
    }
}

$statusRaw = (string)(pickNested($payload, [
    ['status'],
    ['payment_status'],
    ['data', 'status'],
    ['event', 'status']
]) ?? '');

$reference = (string)(pickNested($payload, [
    ['reference'],
    ['external_reference'],
    ['metadata', 'reference'],
    ['data', 'reference'],
    ['data', 'external_reference']
]) ?? '');

$providerTxId = (string)(pickNested($payload, [
    ['id'],
    ['transaction_id'],
    ['txid'],
    ['payment_id'],
    ['data', 'id'],
    ['data', 'transaction_id'],
    ['data', 'txid']
]) ?? '');

$amount = (float)(pickNested($payload, [
    ['amount'],
    ['value'],
    ['data', 'amount'],
    ['data', 'value']
]) ?? 0);

$normalized = normalizePaymentStatus($statusRaw);

appendWebhookLog('WEBHOOK_RECEIVED', [
    'status' => $statusRaw,
    'normalized' => $normalized,
    'reference' => $reference,
    'provider_tx_id' => $providerTxId
]);

if ($normalized === 'paid') {
    if ($reference === '' && $providerTxId === '') {
        appendWebhookLog('PAID_WITHOUT_REFERENCE', ['payload' => $payload]);
        jsonResponse([
            'ok' => false,
            'message' => 'Paid notification without reference/transaction id.'
        ], 422);
    }

    processPaidPayment($reference, $providerTxId, $amount, $payload);
}

jsonResponse([
    'ok' => true,
    'message' => 'Webhook processed.',
    'normalized_status' => $normalized,
    'debug' => $debugEnabled ? [
        'status_raw' => $statusRaw,
        'reference' => $reference,
        'provider_tx_id' => $providerTxId
    ] : null
]);

