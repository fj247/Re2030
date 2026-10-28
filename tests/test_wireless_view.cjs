const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

async function renderTask(report, plots) {
  const elements = new Map();
  const document = {getElementById(id) {
    if (!elements.has(id)) elements.set(id, {hidden:true, style:{}, addEventListener(){}});
    return elements.get(id);
  }};
  const task = {id:'capture-test', created_at:'2026-10-28T00:00:00Z', phase:'ready',
    analysis:'complete', data_ready:true, files:[], bytes:0, plots, analysis_report:report};
  const context = {window:{}, document, setInterval(){}, fetch:async () => ({ok:true,
    json:async () => ({settings:{}, tasks:[task]})})};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,
    '../sim2030/presentation/static/wireless-view.js'), 'utf8'), context);
  context.window.WirelessView.bind();
  await new Promise(resolve => setImmediate(resolve));
  return elements.get('wireless-tasks').innerHTML;
}

test('five independent plots identify first-segment source and actual duration', async () => {
  const names = ['i_envelope.png','q_envelope.png','mean_psd.png','prn_search.png','correlation.png'];
  const html = await renderTask({sourceFile:'segment_000001.iq.f32', sourceDurationSeconds:.05,
    overview:'saved', presence:'inconclusive'}, names);
  assert.equal((html.match(/<figure>/g) || []).length, 5);
  for (const name of names) assert.ok(html.includes(`/files/${name}`));
  assert.ok(html.includes('0.050000 秒（首个分片）'));
  assert.ok(html.includes('不代表全程统计'));
  assert.ok(!html.includes('/files/overview.png'));
});

test('short first segment keeps overview and reports omitted PRN search', async () => {
  const html = await renderTask({sourceFile:'segment_000001.iq.f32', sourceDurationSeconds:.01,
    overview:'saved', presence:'insufficient_samples'}, ['i_envelope.png','q_envelope.png','mean_psd.png']);
  assert.equal((html.match(/<figure>/g) || []).length, 3);
  assert.ok(html.includes('数据不足 20 毫秒，未进行 PRN 搜索'));
  assert.ok(!html.includes('/files/prn_search.png'));
});

test('previously saved composite images remain visible in history', async () => {
  const html = await renderTask({overview:'saved', presence:'inconclusive'},
    ['overview.png','presence.png','correlation.png']);
  assert.equal((html.match(/<figure>/g) || []).length, 3);
  assert.ok(html.includes('历史概览'));
  assert.ok(!html.includes('首个分片'));
});
