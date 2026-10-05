/*
    This file is part of Octra Wallet (webcli).

    Octra Wallet is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    Octra Wallet is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Octra Wallet.  If not, see <http://www.gnu.org/licenses/>.

    This program is released under the GPL with the additional exemption
    that compiling, linking, and/or using OpenSSL is allowed.
    You are free to remove this exemption from derived works.

    Copyright 2025-2026 Octra Labs
              2025-2026 David A.
              2025-2026 Alex T.
              2025-2026 Vadim S.
              2025-2026 Julia L.
*/

import { createAdapter } from './adapter/boot.mjs';

var SWAP_ADDR = 'octBjnQBicZs6iMwcRxrdzLYAzyVTi91KEiA8RGkVjco2w6';
var TOKEN_ADDR = 'oct6J37Wx7Rb1putvfwFrFbGUStE8hGzsb33fhLgUdpTx6d';
var SCANNER_URL = 'https://devnet.octrascan.io';
var TOKEN_SYMBOL = 'tUSD';
var TOKEN_DECIMALS = 6;
var OCT_DECIMALS = 6;

var _dir = 'buy';
var _walletAddr = '';
var _reserveOct = '0';
var _reserveToken = '0';
var _balOctRaw = '0';
var _balTokenRaw = '0';
var _refreshId = null;
var _swapPending = false;

function $(id) { return document.getElementById(id); }

function esc(s) {
  var d = document.createElement('div');
  d.appendChild(document.createTextNode(s));
  return d.innerHTML;
}

async function api(method, path, body) {
  var opts = { method: method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  var res = await fetch('/api' + path, opts);
  var text = await res.text();
  if (!text || text.length === 0) throw new Error('empty response');
  var j;
  try { j = JSON.parse(text); } catch (e) { throw new Error('bad response'); }
  if (!res.ok) throw new Error(j.error || j.message || 'request failed');
  return j;
}

// ---- OctraWalletAdapter wiring (Fase C1; embedded divergence from upstream) ----
// Public endpoints (status/unlock/wallet/receipt/views) keep direct fetch.
// Authed calls (balance, swaps) go through the adapter with 401 re-prompt.
var _adapterBox = null;

async function adapter() {
  if (!_adapterBox) {
    _adapterBox = createAdapter({ appName: 'Octra Swap', promptToken: promptTokenModal });
    var ok = await _adapterBox.adapter.initialize();
    if (!ok) throw new Error('no wallet transport available');
  }
  return _adapterBox;
}

// Single-slot pending prompt: at most one 401 prompt is ever open, because
// withAuthRetry retries once and a second 401 surfaces as a normal error.
var _pendingTokenPrompt = null;

function closeTokenModal(value) {
  $('token-modal').className = 'modal-bg';
  $('token-input').value = '';
  var resolve = _pendingTokenPrompt;
  _pendingTokenPrompt = null;
  if (resolve) resolve(value || null);
}

function saveToken() {
  closeTokenModal($('token-input').value.trim());
}

function cancelToken() {
  closeTokenModal(null);
}

function promptTokenModal(reason) {
  // A second prompt while one is open reuses it rather than stacking modals.
  if (_pendingTokenPrompt) return new Promise(function(r) {
    var prev = _pendingTokenPrompt;
    _pendingTokenPrompt = function(v) { prev(v); r(v); };
  });
  $('token-msg').textContent = reason || 'Paste the Bearer token from Local Web Server settings in the wallet app.';
  $('token-input').value = '';
  $('token-modal').className = 'modal-bg show';
  return new Promise(function(resolve) { _pendingTokenPrompt = resolve; });
}

// Extract a view value from any shape the transports return
// ({result}, {value}, raw primitive).
// Adapter errors carry a numeric code; the page shows code + message so a
// failing branch is diagnosable instead of a bare "undefined".
function adapterMsg(e) {
  if (e && typeof e.code === 'number') return '[' + e.code + '] ' + e.message;
  return e && e.message ? e.message : String(e);
}

function viewVal(r) {
  if (r && typeof r === 'object' && !Array.isArray(r)) {
    if (r.result !== undefined) return r.result;
    if (r.value !== undefined) return r.value;
  }
  return r;
}

function addCommas(s) {
  var parts = s.split('.');
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return parts.join('.');
}

function formatUnits(rawStr, decimals) {
  var dec = parseInt(decimals) || 0;
  var s = String(rawStr).replace(/[^0-9]/g, '');
  if (s === '' || s === '0') return '0';
  if (dec === 0) return s;
  while (s.length <= dec) s = '0' + s;
  var intPart = s.slice(0, s.length - dec);
  var fracPart = s.slice(s.length - dec).replace(/0+$/, '');
  if (!intPart) intPart = '0';
  return fracPart ? intPart + '.' + fracPart : intPart;
}

function parseUnits(humanStr, decimals) {
  var dec = parseInt(decimals) || 0;
  var s = String(humanStr).replace(/,/g, '').trim();
  if (!s || s === '0') return '0';
  var parts = s.split('.');
  var intPart = parts[0] || '0';
  var fracPart = parts[1] || '';
  if (fracPart.length > dec) fracPart = fracPart.slice(0, dec);
  while (fracPart.length < dec) fracPart += '0';
  var raw = intPart + fracPart;
  raw = raw.replace(/^0+/, '') || '0';
  return raw;
}

function bigMul(a, b) {
  return String(BigInt(a) * BigInt(b));
}

function bigDiv(a, b) {
  if (b === '0') return '0';
  return String(BigInt(a) / BigInt(b));
}

function bigAdd(a, b) {
  return String(BigInt(a) + BigInt(b));
}

function bigSub(a, b) {
  var r = BigInt(a) - BigInt(b);
  return r < 0n ? '0' : String(r);
}

function bigGt(a, b) {
  return BigInt(a) > BigInt(b);
}

function bigGte(a, b) {
  return BigInt(a) >= BigInt(b);
}

function calcOutput(reserveIn, reserveOut, amountIn) {
  if (amountIn === '0' || reserveIn === '0') return '0';
  return bigDiv(bigMul(reserveOut, amountIn), bigAdd(reserveIn, amountIn));
}

function calcPriceImpact(reserveIn, amountIn) {
  if (reserveIn === '0' || amountIn === '0') return 0;
  return (Number(amountIn) / Number(amountIn) + Number(reserveIn)) * 100;
}

function txUrl(hash) {
  return SCANNER_URL + '/tx.html?hash=' + encodeURIComponent(hash);
}

async function checkWallet() {
  try {
    var st = await api('GET', '/wallet/status');
    if (st.loaded) {
      var info = await api('GET', '/wallet');
      _walletAddr = info.address || '';
      $('unlock-view').style.display = 'none';
      $('swap-view').style.display = 'block';
      $('wallet-addr').textContent = _walletAddr.slice(0, 8) + '...' + _walletAddr.slice(-6);
      loadAll();
      _refreshId = setInterval(loadAll, 10000);
      return;
    }
    if (st.has_encrypted || st.has_legacy) {
      $('unlock-view').style.display = 'block';
      $('swap-view').style.display = 'none';
      return;
    }
    $('unlock-view').style.display = 'block';
    $('swap-view').style.display = 'none';
    $('unlock-err').textContent = 'no wallet found. create one in the main wallet app first.';
    $('unlock-err').className = 'status-msg err';
  } catch (e) {
    $('unlock-view').style.display = 'block';
    $('swap-view').style.display = 'none';
    $('unlock-err').textContent = 'cannot connect to wallet';
    $('unlock-err').className = 'status-msg err';
  }
}

async function doUnlock() {
  var pin = $('pin-input').value.trim();
  if (pin.length < 4) return;
  try {
    await api('POST', '/wallet/unlock', { pin: pin });
    $('unlock-err').className = 'status-msg';
    checkWallet();
  } catch (e) {
    $('unlock-err').textContent = e.message || 'wrong pin';
    $('unlock-err').className = 'status-msg err';
  }
}

async function loadAll() {
  await Promise.all([loadReserves(), loadBalances()]);
  updatePrice();
  onInputChange();
}

async function loadReserves() {
  try {
    var box = await adapter();
    var r = await box.adapter.contractView({ contract: SWAP_ADDR, method: 'get_reserves', params: [] });
    var v = viewVal(r);
    if (v === undefined || v === null) v = '';
    var parts = String(v).split(':');
    if (parts.length === 2) {
      _reserveOct = parts[0];
      _reserveToken = parts[1];
    }
    $('pool-info').textContent = addCommas(formatUnits(_reserveOct, OCT_DECIMALS)) + ' OCT / ' + addCommas(formatUnits(_reserveToken, TOKEN_DECIMALS)) + ' ' + TOKEN_SYMBOL;
  } catch (e) {
    $('pool-info').textContent = 'failed to load reserves';
  }
}

async function loadBalances() {
  var box = await adapter();
  try {
    var bal = await box.withAuthRetry(function() { return box.adapter.getBalance(); });
    var rawBal = bal && bal.raw !== undefined && bal.raw !== null ? bal.raw : parseUnits((bal && bal.public) || '0', OCT_DECIMALS);
    _balOctRaw = String(rawBal);
    $('bal-oct').textContent = addCommas(formatUnits(_balOctRaw, OCT_DECIMALS));
  } catch (e) {
    // A missing/unauthorized balance must not blank the form; show why.
    $('bal-oct').textContent = adapterMsg(e);
  }
  try {
    var r = await box.adapter.contractView({ contract: TOKEN_ADDR, method: 'balance_of', params: [_walletAddr] });
    _balTokenRaw = String(viewVal(r) || '0');
    $('bal-tusd').textContent = addCommas(formatUnits(_balTokenRaw, TOKEN_DECIMALS));
  } catch (e) {
    $('bal-tusd').textContent = adapterMsg(e);
  }
}

function updatePrice() {
  if (_reserveToken === '0') {
    $('price-display').textContent = '...';
    return;
  }
  var price = Number(_reserveToken) / Number(_reserveOct);
  $('price-display').textContent = price.toFixed(6) + ' ' + TOKEN_SYMBOL;
}

function setDir(d) {
  _dir = d;
  $('tab-buy').className = d === 'buy' ? 'active' : '';
  $('tab-sell').className = d === 'sell' ? 'active' : '';
  $('swap-input').value = '';
  if (d === 'buy') {
    $('input-label').textContent = 'you pay';
    $('input-token').textContent = 'OCT';
    $('output-token').textContent = TOKEN_SYMBOL;
  } else {
    $('input-label').textContent = 'you pay';
    $('input-token').textContent = TOKEN_SYMBOL;
    $('output-token').textContent = 'OCT';
  }
  onInputChange();
}

function setMax() {
  if (_dir === 'buy') {
    var maxOct = bigSub(_balOctRaw, parseUnits('100', OCT_DECIMALS));
    if (bigGt('0', maxOct)) maxOct = '0';
    $('swap-input').value = formatUnits(maxOct, OCT_DECIMALS);
  } else {
    $('swap-input').value = formatUnits(_balTokenRaw, TOKEN_DECIMALS);
  }
  onInputChange();
}

function onInputChange() {
  var raw = $('swap-input').value.trim();
  var btn = $('swap-btn');
  if (!raw || raw === '0' || raw === '0.0') {
    $('output-val').textContent = '0';
    $('impact-val').textContent = '-';
    btn.textContent = 'enter amount';
    btn.disabled = true;
    return;
  }
  var amountRaw;
  if (_dir === 'buy') {
    amountRaw = parseUnits(raw, OCT_DECIMALS);
    if (bigGt(amountRaw, _balOctRaw)) {
      btn.textContent = 'insufficient OCT';
      btn.disabled = true;
      $('output-val').textContent = '0';
      return;
    }
    var outRaw = calcOutput(_reserveOct, _reserveToken, amountRaw);
    $('output-val').textContent = addCommas(formatUnits(outRaw, TOKEN_DECIMALS));
    var impact = (Number(amountRaw) / (Number(amountRaw) + Number(_reserveOct))) * 100;
    $('impact-val').textContent = impact.toFixed(2) + '%';
    btn.textContent = 'swap OCT -> ' + TOKEN_SYMBOL;
    btn.disabled = false;
  } else {
    amountRaw = parseUnits(raw, TOKEN_DECIMALS);
    if (bigGt(amountRaw, _balTokenRaw)) {
      btn.textContent = 'insufficient ' + TOKEN_SYMBOL;
      btn.disabled = true;
      $('output-val').textContent = '0';
      return;
    }
    var outRawS = calcOutput(_reserveToken, _reserveOct, amountRaw);
    $('output-val').textContent = addCommas(formatUnits(outRawS, OCT_DECIMALS));
    var impactS = (Number(amountRaw) / (Number(amountRaw) + Number(_reserveToken))) * 100;
    $('impact-val').textContent = impactS.toFixed(2) + '%';
    btn.textContent = 'swap ' + TOKEN_SYMBOL + ' -> OCT';
    btn.disabled = false;
  }
}

function doSwap() {
  if (_swapPending) return;
  var raw = $('swap-input').value.trim();
  if (!raw) return;
  var amountRaw, outRaw, payStr, receiveStr;
  if (_dir === 'buy') {
    amountRaw = parseUnits(raw, OCT_DECIMALS);
    outRaw = calcOutput(_reserveOct, _reserveToken, amountRaw);
    payStr = addCommas(formatUnits(amountRaw, OCT_DECIMALS)) + ' OCT';
    receiveStr = '~' + addCommas(formatUnits(outRaw, TOKEN_DECIMALS)) + ' ' + TOKEN_SYMBOL;
  } else {
    amountRaw = parseUnits(raw, TOKEN_DECIMALS);
    outRaw = calcOutput(_reserveToken, _reserveOct, amountRaw);
    payStr = addCommas(formatUnits(amountRaw, TOKEN_DECIMALS)) + ' ' + TOKEN_SYMBOL;
    receiveStr = '~' + addCommas(formatUnits(outRaw, OCT_DECIMALS)) + ' OCT';
  }
  $('confirm-detail').innerHTML =
    '<div class="cd-row"><span>you pay</span><span class="cd-val">' + esc(payStr) + '</span></div>' +
    '<div class="cd-row"><span>you receive</span><span class="cd-val">' + esc(receiveStr) + '</span></div>' +
    '<div class="cd-row"><span>fee</span><span class="cd-val">0.1 OCT</span></div>';
  $('confirm-modal').className = 'modal-bg show';
}

function cancelSwap() {
  $('confirm-modal').className = 'modal-bg';
}

function showProgress(steps) {
  var el = $('progress-area');
  var h = '';
  for (var i = 0; i < steps.length; i++) {
    var s = steps[i];
    if (s.link) {
      h += '<div class="step ' + s.cls + '">' + esc(s.text) + ' <a href="' + esc(s.link) + '" target="_blank" style="color:inherit;border-bottom:1px solid #D0D7E2;text-decoration:none;font-family:monospace;font-size:10px">' + esc(s.linkText || 'view tx') + '</a></div>';
    } else {
      h += '<div class="step ' + s.cls + '">' + esc(s.text) + '</div>';
    }
  }
  el.innerHTML = h;
  el.style.display = 'block';
}

function showStatus(msg, cls) {
  var el = $('status-area');
  el.textContent = msg;
  el.className = 'status-msg ' + cls;
}

function clearStatus() {
  $('status-area').className = 'status-msg';
  $('progress-area').style.display = 'none';
}

async function waitReceipt(txHash) {
  var lastReceiptError = null;
  for (var i = 0; i < 60; i++) {
    try {
      var r = await api('GET', '/contract/receipt?hash=' + encodeURIComponent(txHash));
      if (r && r.success !== undefined) return r;
    } catch (e) {
      // Not mined yet (or a transient server hiccup) — keep polling until
      // the bounded attempt count is exhausted, then report the timeout.
      lastReceiptError = e;
    }
    await new Promise(function(ok) { setTimeout(ok, 1000); });
  }
  throw new Error('timeout waiting for receipt' + (lastReceiptError ? ': ' + adapterMsg(lastReceiptError) : ''));
}

async function confirmSwap() {
  $('confirm-modal').className = 'modal-bg';
  _swapPending = true;
  $('swap-btn').className = 'swap-btn loading';
  $('swap-btn').textContent = 'processing...';
  clearStatus();
  var raw = $('swap-input').value.trim();
  try {
    if (_dir === 'buy') {
      await doBuySwap(raw);
    } else {
      await doSellSwap(raw);
    }
  } catch (e) {
    showStatus(e.message || 'swap failed', 'err');
  }
  _swapPending = false;
  $('swap-btn').className = 'swap-btn';
  await loadAll();
  $('swap-input').value = '';
  onInputChange();
}

async function doBuySwap(humanAmount) {
  var amountRaw = parseUnits(humanAmount, OCT_DECIMALS);
  showProgress([{ text: 'swapping OCT -> ' + TOKEN_SYMBOL + '...', cls: 'active' }]);
  var box = await adapter();
  var r = await box.withAuthRetry(function() {
    return box.adapter.callContract({ contract: SWAP_ADDR, method: 'swap_oct_to_token', params: [], amount: amountRaw });
  });
  var buyHash = r.txHash;
  if (!buyHash) throw new Error('no tx_hash');
  showProgress([{ text: 'swapping OCT -> ' + TOKEN_SYMBOL + '... tx: ' + buyHash.slice(0, 10), cls: 'active' }]);
  var receipt = await waitReceipt(buyHash);
  if (!receipt.success) throw new Error(receipt.error || 'swap reverted');
  showProgress([{ text: 'swap complete', cls: 'done', link: txUrl(buyHash), linkText: buyHash.slice(0, 16) + '...' }]);
}

async function doSellSwap(humanAmount) {
  var amountRaw = parseUnits(humanAmount, TOKEN_DECIMALS);
  showProgress([
    { text: '1/2 granting ' + TOKEN_SYMBOL + ' access...', cls: 'active' },
    { text: '2/2 swap ' + TOKEN_SYMBOL + ' -> OCT', cls: '' }
  ]);
  var gbox = await adapter();
  var g = await gbox.withAuthRetry(function() {
    return gbox.adapter.callContract({ contract: TOKEN_ADDR, method: 'grant', params: [SWAP_ADDR, parseInt(amountRaw)] });
  });
  var grantHash = g.txHash;
  if (!grantHash) throw new Error('grant: no tx_hash');
  var gr = await waitReceipt(grantHash);
  if (!gr.success) throw new Error('grant failed: ' + (gr.error || 'reverted'));
  showProgress([
    { text: '1/2 grant approved', cls: 'done', link: txUrl(grantHash), linkText: grantHash.slice(0, 16) + '...' },
    { text: '2/2 swapping ' + TOKEN_SYMBOL + ' -> OCT...', cls: 'active' }
  ]);
  var sbox = await adapter();
  var r = await sbox.withAuthRetry(function() {
    return sbox.adapter.callContract({ contract: SWAP_ADDR, method: 'swap_token_to_oct', params: [parseInt(amountRaw)] });
  });
  var sellHash = r.txHash;
  if (!sellHash) throw new Error('swap: no tx_hash');
  showProgress([
    { text: '1/2 grant approved', cls: 'done', link: txUrl(grantHash), linkText: grantHash.slice(0, 16) + '...' },
    { text: '2/2 swapping... tx: ' + sellHash.slice(0, 10), cls: 'active' }
  ]);
  var receipt = await waitReceipt(sellHash);
  if (!receipt.success) throw new Error('swap reverted: ' + (receipt.error || ''));
  showProgress([
    { text: '1/2 grant approved', cls: 'done', link: txUrl(grantHash), linkText: grantHash.slice(0, 16) + '...' },
    { text: '2/2 swap complete', cls: 'done', link: txUrl(sellHash), linkText: sellHash.slice(0, 16) + '...' }
  ]);
}

$('pin-input').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') doUnlock();
});

$('token-input').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') saveToken();
  if (e.key === 'Escape') cancelToken();
});

checkWallet();

(function() {
  var actions = { doUnlock, setDir, onInputChange, setMax, doSwap, cancelSwap, confirmSwap, saveToken, cancelToken };
  function run(e, attr) {
    var el = e.target.closest('[' + attr + ']');
    if (!el) return;
    var fn = actions[el.getAttribute(attr)];
    if (!fn) return;
    if (el.getAttribute('data-prevent') === '1') e.preventDefault();
    fn(el.getAttribute('data-arg'), el, e);
  }
  document.addEventListener('click', function(e) { run(e, 'data-action'); });
  document.addEventListener('input', function(e) { run(e, 'data-input'); });
})();