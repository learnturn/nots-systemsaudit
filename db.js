/* NOTS Quality Audit — Supabase data layer.
   Talks to Supabase's REST API with plain fetch: no SDK, nothing to bundle.
   Exposes window.NOTSDB. If no credentials are configured the app falls back
   to browser-local storage and says so in the header. */
(function () {
  var cfg = window.NOTS_SUPABASE || {};
  var URL_BASE = String(cfg.url || '').replace(/\/+$/, '');
  var KEY = String(cfg.anonKey || '');
  var REST = URL_BASE + '/rest/v1';

  function headers(extra) {
    var h = { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' };
    if (extra) for (var k in extra) h[k] = extra[k];
    return h;
  }

  function req(path, opts) {
    opts = opts || {};
    return fetch(REST + path, {
      method: opts.method || 'GET',
      headers: headers(opts.headers),
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (r) {
      return r.text().then(function (t) {
        if (!r.ok) throw new Error('Supabase ' + r.status + ': ' + t.slice(0, 300));
        return t ? JSON.parse(t) : null;
      });
    });
  }

  var d = function (v) { return (v === '' || v == null) ? null : v; };       // date/number out
  var s = function (v) { return v == null ? '' : String(v); };               // text in
  var n = function (v) { return (v === '' || v == null) ? null : Number(v); };

  function rowToProcess(p, cps) {
    return {
      id: p.id, name: p.name, area: p.area, auditType: p.audit_type, site: p.site,
      checkpoints: cps.filter(function (c) { return c.process_id === p.id; })
        .sort(function (a, b) { return a.position - b.position; })
        .map(function (c) { return { id: c.id, text: c.text, standard: c.standard, category: c.category, severity: c.severity }; })
    };
  }

  function rowToAudit(a, results) {
    return {
      id: a.id, date: a.date, site: a.site, auditeeName: a.auditee_name, auditeeNo: a.auditee_no,
      customer: a.customer, shift: a.shift, layer: a.layer, auditType: a.audit_type, area: a.area,
      processId: a.process_id, processName: a.process_name, auditor: a.auditor,
      audited: a.checkpoints_audited, conforming: a.conforming, pct: Number(a.pct),
      result: a.result, notes: a.notes,
      checkpoints: results.filter(function (r) { return r.audit_id === a.id; })
        .sort(function (x, y) { return x.position - y.position; })
        .map(function (r) { return { text: r.text, standard: r.standard, result: r.result, note: r.note, findingId: r.finding_id || '' }; })
    };
  }

  function rowToFinding(f, notes, retrain) {
    var rt = retrain.find(function (r) { return r.finding_id === f.id; }) || {};
    return {
      id: f.id, auditId: f.audit_id, date: f.date, site: f.site, customer: f.customer, shift: f.shift,
      area: f.area, auditType: f.audit_type, auditor: f.auditor, processName: f.process_name,
      auditeeName: f.auditee_name, employee: f.employee, category: f.category,
      breakDetail: f.break_detail, standard: f.standard, severity: f.severity,
      impact: f.impact, containment: f.containment,
      repeat: f.repeat_status, repeatByEmployee: f.repeat_by_employee || [], repeatByType: f.repeat_by_type || [],
      reason: f.reason, rootCause: f.root_cause, cmType: f.cm_type, owner: f.owner,
      target: s(f.target_date), actual: s(f.actual_date), status: f.status,
      effect: f.effectiveness, reported: f.reported_to_customer, retrainUsed: !!f.retrain_used,
      retrain: {
        removed: rt.removed || 'No', removedDate: s(rt.removed_date), topic: s(rt.topic),
        trainer: s(rt.trainer), trainDate: s(rt.train_date), method: s(rt.method),
        monStart: s(rt.mon_start), monEnd: s(rt.mon_end), monObs: s(rt.mon_observations),
        monBy: s(rt.mon_by), monErrors: s(rt.mon_errors), checkDate: s(rt.check_date),
        checkBy: s(rt.check_by), checkResult: s(rt.check_result), outcome: s(rt.outcome),
        narrative: s(rt.narrative)
      },
      notes: notes.filter(function (x) { return x.finding_id === f.id; })
        .map(function (x) { return { ts: x.created_at, author: x.author, text: x.text }; })
    };
  }

  function findingToRow(f) {
    return {
      repeat_status: f.repeat, reason: f.reason, root_cause: f.rootCause, cm_type: f.cmType,
      owner: f.owner, target_date: d(f.target), actual_date: d(f.actual), status: f.status,
      effectiveness: f.effect, reported_to_customer: f.reported, retrain_used: !!f.retrainUsed,
      updated_at: new Date().toISOString()
    };
  }

  function retrainToRow(id, r) {
    return {
      finding_id: id, removed: r.removed, removed_date: d(r.removedDate), topic: r.topic,
      trainer: r.trainer, train_date: d(r.trainDate), method: r.method,
      mon_start: d(r.monStart), mon_end: d(r.monEnd), mon_observations: n(r.monObs),
      mon_by: r.monBy, mon_errors: n(r.monErrors), check_date: d(r.checkDate),
      check_by: r.checkBy, check_result: r.checkResult, outcome: r.outcome, narrative: r.narrative
    };
  }

  var LIMIT = '&limit=5000';

  window.NOTSDB = {
    configured: !!(URL_BASE && KEY),

    loadAll: function () {
      return Promise.all([
        req('/users?select=*&order=position.asc' + LIMIT),
        req('/processes?select=*&order=position.asc' + LIMIT),
        req('/process_checkpoints?select=*' + LIMIT),
        req('/audits?select=*&order=created_at.desc' + LIMIT),
        req('/audit_results?select=*' + LIMIT),
        req('/findings?select=*&order=created_at.asc' + LIMIT),
        req('/finding_notes?select=*&order=created_at.desc' + LIMIT),
        req('/finding_retraining?select=*' + LIMIT),
        req('/settings?select=*&id=eq.1')
      ]).then(function (res) {
        var st = (res[8] && res[8][0]) || { conformance_target: 95, repeat_window_days: 90 };
        return {
          users: res[0].map(function (u) { return { id: u.id, name: u.name, employeeNo: u.employee_no, site: u.site, role: u.role }; }),
          processes: res[1].map(function (p) { return rowToProcess(p, res[2]); }),
          audits: res[3].map(function (a) { return rowToAudit(a, res[4]); }),
          findings: res[5].map(function (f) { return rowToFinding(f, res[6], res[7]); }),
          settings: { target: st.conformance_target, window: st.repeat_window_days },
          seq: { audit: 0, finding: 0 }
        };
      });
    },

    // One atomic call — audit, checkpoint results, findings and retraining rows
    // land together. Returns { auditId, findingIds }.
    submitAudit: function (payload) {
      return req('/rpc/submit_audit', { method: 'POST', body: { payload: payload } });
    },

    updateFinding: function (f) {
      return req('/findings?id=eq.' + encodeURIComponent(f.id), { method: 'PATCH', body: findingToRow(f) })
        .then(function () {
          return req('/finding_retraining', {
            method: 'POST',
            headers: { Prefer: 'resolution=merge-duplicates' },
            body: retrainToRow(f.id, f.retrain)
          });
        });
    },

    addNote: function (findingId, note) {
      return req('/finding_notes', { method: 'POST', body: { finding_id: findingId, author: note.author, text: note.text } });
    },

    deleteAudit: function (id) {
      return req('/audits?id=eq.' + encodeURIComponent(id), { method: 'DELETE' });
    },

    saveProcess: function (p, position) {
      return req('/processes', {
        method: 'POST',
        headers: { Prefer: 'resolution=merge-duplicates' },
        body: { id: p.id, name: p.name, area: p.area, audit_type: p.auditType, site: p.site, position: position || 0 }
      }).then(function () {
        return req('/process_checkpoints?process_id=eq.' + encodeURIComponent(p.id), { method: 'DELETE' });
      }).then(function () {
        if (!p.checkpoints.length) return null;
        return req('/process_checkpoints', {
          method: 'POST',
          body: p.checkpoints.map(function (c, i) {
            return { id: c.id, process_id: p.id, position: i, text: c.text, standard: c.standard, category: c.category, severity: c.severity };
          })
        });
      });
    },

    deleteProcess: function (id) {
      return req('/processes?id=eq.' + encodeURIComponent(id), { method: 'DELETE' });
    },

    saveUser: function (u, position) {
      return req('/users', {
        method: 'POST',
        headers: { Prefer: 'resolution=merge-duplicates' },
        body: { id: u.id, name: u.name, employee_no: u.employeeNo, site: u.site, role: u.role, position: position || 0 }
      });
    },

    deleteUser: function (id) {
      return req('/users?id=eq.' + encodeURIComponent(id), { method: 'DELETE' });
    },

    saveSettings: function (settings) {
      return req('/settings?id=eq.1', {
        method: 'PATCH',
        body: { conformance_target: settings.target, repeat_window_days: settings.window }
      });
    }
  };
})();
