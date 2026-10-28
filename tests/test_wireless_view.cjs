const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

async function renderTask(report, charts=[], plots=[], receiver={detail:'接收装置已就绪'}) {
  const elements = new Map(), mounted=[];
  const document = {getElementById(id) {
    if (!elements.has(id)) elements.set(id, {hidden:true, style:{}, addEventListener(){}});
    return elements.get(id);
  }};
  const task = {id:'capture-test', created_at:'2026-10-28T00:00:00Z', phase:'generating',
    analysis:'running', data_ready:false, files:[], bytes:0, charts, plots, analysis_report:report};
  const context = {window:{WirelessCharts:{mount(element,data){mounted.push(data);}}}, document, setInterval(){},
    fetch:async url => ({ok:true, json:async () => url==='/api/wireless'?
      {settings:{}, tasks:[task], receiver}:{kind:url.split('/').pop()}})};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,
    '../sim2030/presentation/static/wireless-view.js'), 'utf8'), context);
  context.window.WirelessView.bind();
  await new Promise(resolve => setImmediate(resolve));
  return {html:elements.get('wireless-tasks').innerHTML, mounted,
    receiver:elements.get('wireless-receiver').textContent};
}

test('three numeric charts render while capture continues; requested wording is respected', async () => {
  const {html,mounted,receiver} = await renderTask({sourceFile:'segment_000001.iq.f32',
    sourceDurationSeconds:.05, spectrum:'saved', search:'saved', correlation:'saved',
    presence:'supported_in_tested_windows'}, ['mean_psd.json','prn_search.json','correlation.json']);
  assert.equal((html.match(/<figure/g) || []).length, 3);
  assert.equal(mounted.length,3);
  assert.ok(!html.includes('<img'));
  assert.ok(html.includes('0.050000 秒（首个分片）'));
  assert.ok(html.includes('PRN 证据：所检窗口支持目标 PRN 结构'));
  assert.ok(html.includes('平均功率谱：已生成'));
  assert.ok(!html.includes('概览：'));
  assert.ok(!html.includes('不代表全程统计'));
  assert.ok(!html.includes('身份识别'));
  assert.equal(receiver,'接收装置已就绪');
});

test('PSD is displayed before PRN search completes', async () => {
  const {html,mounted} = await renderTask({sourceFile:'segment_000001.iq.f32',
    sourceDurationSeconds:.05, spectrum:'saved', search:'pending', correlation:'pending', presence:'pending'},
    ['mean_psd.json']);
  assert.equal(mounted.length,1);
  assert.ok(html.includes('相关搜索图：计算中'));
  assert.ok(html.includes('PRN 证据：分析中'));
});

test('short first segment reports omitted search and does not add missing charts', async () => {
  const {html,mounted} = await renderTask({sourceFile:'segment_000001.iq.f32',sourceDurationSeconds:.01,
    spectrum:'saved',presence:'insufficient_samples'}, ['mean_psd.json']);
  assert.equal(mounted.length,1);
  assert.ok(html.includes('数据不足 20 毫秒，未进行 PRN 搜索'));
  assert.ok(!html.includes('wireless-chart-search'));
});

test('history keeps remaining three images, with no I/Q envelope figures', async () => {
  const {html} = await renderTask({overview:'saved',presence:'inconclusive'}, [],
    ['i_envelope.png','q_envelope.png','mean_psd.png','prn_search.png','correlation.png']);
  assert.equal((html.match(/<figure/g) || []).length,3);
  assert.ok(!html.includes('/files/i_envelope.png'));
  assert.ok(!html.includes('/files/q_envelope.png'));
  assert.ok(html.includes('历史图片'));
});
