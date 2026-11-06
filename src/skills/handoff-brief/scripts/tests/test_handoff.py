#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
"""Tests de handoff.py: unittest, sin red y sin tocar el proyecto real.

Cada caso crea un proyecto temporal y ejecuta el script como proceso aparte
(`python3 handoff.py <cmd>`) con `cwd` en ese proyecto. `opencode` se reemplaza por
un stub en un bin/ temporal que registra el cuerpo JSON y devuelve un SID fijo.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import date
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "handoff.py"
SLUG_PATTERN = r"\A[a-z0-9][a-z0-9-]{0,39}\Z"

FAKE_OPENCODE = '''#!/usr/bin/env python3
import json, os, sys

with open(os.environ["FAKE_OPENCODE_LOG"], "a", encoding="utf-8") as handle:
    handle.write(json.dumps({"argv": sys.argv[1:]}) + "\\n")

args = sys.argv[1:]
if args[:3] == ["api", "get", "/api/agent"]:
    print(json.dumps({"data": [{"id": "build"}, {"id": "demo"}, {"id": "compaction", "hidden": True}]}))
elif args[:3] == ["api", "post", "/api/session"]:
    print(json.dumps({"data": {"id": "ses_test"}}))
else:
    print("{}")
'''


def today():
    return date.today().isoformat()


class HandoffTestCase(unittest.TestCase):
    """Proyecto temporal aislado + helpers de aserción sobre stdout/stderr del script."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.project = self.tmp / "proyecto"
        self.handoffs = self.project / ".opencode" / "handoffs"
        self.config = self.tmp / "config"
        self.project.mkdir()
        self.config.mkdir()

    # --- ejecución -------------------------------------------------------

    def run_handoff(self, *args, env=None, timeout=None):
        environment = dict(os.environ, XDG_CONFIG_HOME=str(self.config))
        environment.update(env or {})
        return subprocess.run(
            [sys.executable, str(SCRIPT)] + list(args),
            check=False, cwd=str(self.project), capture_output=True, text=True, env=environment,
            timeout=timeout)

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def fails(self, result, code=1):
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def value(self, result, key):
        prefix = key + "="
        return next(line[len(prefix):] for line in result.stdout.splitlines() if line.startswith(prefix))

    # --- fixtures --------------------------------------------------------

    def make_handoffs(self):
        self.handoffs.mkdir(parents=True, exist_ok=True)
        return self.handoffs

    def write_work_file(self, name, content):
        self.make_handoffs()
        path = self.handoffs / name
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def age_file(self, path, days):
        stamp = time.time() - days * 86400
        os.utime(str(path), (stamp, stamp))

    def make_briefs(self, count, age_days=None):
        """Crea `count` hojas (la 0 es la más nueva) y devuelve la lista en ese orden."""
        self.make_handoffs()
        briefs = []
        for index in range(count):
            brief = self.handoffs / f"{today()}-hoja-{index:02d}.md"
            brief.write_text("# hoja\n", encoding="utf-8")
            self.age_file(brief, age_days if age_days is not None else index / 24)
            briefs.append(brief)
        return briefs

    def make_brief(self, slug="demo", text="# Hand-off: demo\n\nPlan.\n"):
        self.make_handoffs()
        path = self.handoffs / f"{today()}-{slug}.md"
        path.write_text(text, encoding="utf-8")
        return path

    def seed_state(self, brief, slug="demo", digest=None, **extra):
        state = {"slug": slug, "brief": str(brief)}
        if digest is not None:
            state["hash"] = digest
        state.update(extra)
        self.write_work_file(".state", json.dumps(state))

    def seed_agent(self, agent_id="demo", project_local=True):
        base = self.project / ".opencode" / "agents" if project_local else self.config / "opencode" / "agent"
        base.mkdir(parents=True, exist_ok=True)
        path = base / (agent_id + ".md")
        path.write_text("---\nmode: all\npermissions:\n  bash: allow\n---\n\nAgente.\n", encoding="utf-8")
        return path

    def install_fake_opencode(self):
        binary_dir = self.tmp / "bin"
        binary_dir.mkdir(exist_ok=True)
        stub = binary_dir / "opencode"
        stub.write_text(FAKE_OPENCODE, encoding="utf-8")
        stub.chmod(0o755)
        self.log = self.tmp / "opencode.log"
        self.log.write_text("", encoding="utf-8")
        return {"PATH": str(binary_dir) + os.pathsep + os.environ.get("PATH", ""),
                "FAKE_OPENCODE_LOG": str(self.log)}

    def logged_bodies(self):
        calls = [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines() if line]
        return [json.loads(argv[argv.index("-d") + 1]) for argv in (call["argv"] for call in calls)
                if "-d" in argv]

    def digest_of(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()


class PrepTest(HandoffTestCase):
    def test_prep_crea_directorio_y_limpia_estado_viejo(self):
        for name in (".agent", ".task", ".candidates", ".state"):
            self.write_work_file(name, "viejo")

        result = self.ok(self.run_handoff("prep"))

        self.assertIn("OK prep", result.stdout)
        self.assertTrue(self.handoffs.is_dir())
        for name in (".agent", ".task", ".candidates", ".state"):
            self.assertFalse((self.handoffs / name).exists(), name)

    def test_prep_borra_agent_symlink_sin_tocar_la_victima(self):
        victim = self.tmp / "victima.txt"
        victim.write_text("original\n", encoding="utf-8")
        self.make_handoffs()
        os.symlink(str(victim), str(self.handoffs / ".agent"))

        self.ok(self.run_handoff("prep"))

        self.assertFalse((self.handoffs / ".agent").is_symlink())
        self.assertFalse((self.handoffs / ".agent").exists())
        self.assertEqual(victim.read_text(encoding="utf-8"), "original\n")

    def test_prep_falla_si_handoffs_es_symlink(self):
        self.project.joinpath(".opencode").mkdir()
        outside = self.tmp / "afuera"
        outside.mkdir()
        os.symlink(str(outside), str(self.handoffs))

        result = self.fails(self.run_handoff("prep"))

        self.assertIn("symlink", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_prep_falla_si_opencode_apunta_afuera(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        os.symlink(str(outside), str(self.project / ".opencode"))

        self.fails(self.run_handoff("prep"))

        self.assertEqual(list(outside.iterdir()), [])

    def test_prep_rechaza_raiz_invalida(self):
        for invalid in ("/", ".", str(self.project) + "/.."):
            with self.subTest(root=invalid):
                self.fails(self.run_handoff("--project", invalid, "prep"))


class ScanTest(HandoffTestCase):
    def test_scan_detecta_los_dos_excedentes(self):
        briefs = self.make_briefs(12)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=2", result.stdout)
        candidates = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(sorted(candidates), sorted(str(path) for path in briefs[-2:]))
        self.assertEqual((self.handoffs / ".candidates").stat().st_mode & 0o777, 0o600)

    def test_scan_incluye_hoja_de_20_dias(self):
        briefs = self.make_briefs(2)
        vieja = self.handoffs / f"{today()}-vieja.md"
        vieja.write_text("# hoja\n", encoding="utf-8")
        self.age_file(vieja, 20)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=1", result.stdout)
        stored = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(stored, [str(vieja)])
        self.assertTrue(all(path.exists() for path in briefs))

    def test_scan_no_ejecuta_nombres_hostiles(self):
        self.make_handoffs()
        hostile = self.handoffs / f"{today()}-pwned $(touch PWNED) `touch PWNED2`.md"
        hostile.write_text("# hoja\n", encoding="utf-8")
        self.age_file(hostile, 5)
        self.make_briefs(11)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=2", result.stdout)
        self.assertIn("$(touch PWNED)", result.stdout)
        for pwned in ("PWNED", "PWNED2"):
            self.assertFalse((self.project / pwned).exists(), pwned)
            self.assertFalse((self.tmp / pwned).exists(), pwned)

    def test_scan_ignora_subdirectorios(self):
        self.make_handoffs()
        nested = self.handoffs / "sub"
        nested.mkdir()
        inner = nested / f"{today()}-inner.md"
        inner.write_text("# hoja\n", encoding="utf-8")
        self.age_file(inner, 40)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("nada para borrar", result.stdout)
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_scan_y_delete_borran_nombre_con_salto_de_linea(self):
        self.make_handoffs()
        hostile = self.handoffs / f"{today()}-evil\\nANSI.md"
        hostile.write_text("# hoja\n", encoding="utf-8")
        self.age_file(hostile, 30)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=1", result.stdout)
        stored = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(stored, [str(hostile)])

        deleted = self.ok(self.run_handoff("delete"))

        self.assertIn("BORRADOS=1 FALLOS=0", deleted.stdout)
        self.assertFalse(hostile.exists())

    def test_scan_rechaza_candidates_fifo_sin_colgarse(self):
        brief = self.make_brief("vieja")
        self.age_file(brief, 30)
        os.mkfifo(str(self.handoffs / ".candidates"))

        result = self.fails(self.run_handoff("scan", timeout=15))

        self.assertIn("no regular", result.stderr)


class DeleteTest(HandoffTestCase):
    def test_delete_respeta_guards_y_no_corta_en_el_primer_fallo(self):
        first = self.make_brief("uno")
        second = self.make_brief("dos")
        intacto = self.make_brief("intacto")
        nested = self.handoffs / "sub"
        nested.mkdir()
        inner = nested / "inner.md"
        inner.write_text("# inner\n", encoding="utf-8")
        outside = self.tmp / "victima.md"
        outside.write_text("# victima\n", encoding="utf-8")
        link = self.handoffs / f"{today()}-link.md"
        os.symlink(str(outside), str(link))
        (self.handoffs / ".candidates").write_text(
            json.dumps([str(link), str(second), str(inner), str(first)]), encoding="utf-8")

        result = self.fails(self.run_handoff("delete"))

        self.assertIn("BORRADOS=2 FALLOS=2", result.stdout)
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())
        self.assertTrue(link.is_symlink())
        self.assertTrue(outside.exists())
        self.assertTrue(inner.exists())
        self.assertTrue(intacto.exists())
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_delete_sin_candidates_falla(self):
        self.make_handoffs()
        self.assertIn("scan", self.fails(self.run_handoff("delete")).stderr)

    def test_discard_borra_candidates(self):
        self.write_work_file(".candidates", json.dumps(["/tmp/x.md"]))
        result = self.ok(self.run_handoff("discard"))
        self.assertIn("descartado", result.stdout)
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_discard_falla_si_handoffs_es_symlink(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        (outside / ".candidates").write_text("[]", encoding="utf-8")
        self.project.joinpath(".opencode").mkdir()
        os.symlink(str(outside), str(self.handoffs))

        self.fails(self.run_handoff("discard"))

        self.assertTrue((outside / ".candidates").exists())


class SlugTest(HandoffTestCase):
    def test_slug_sanea_acentos_comillas_saltos_y_nul(self):
        task = "Migrar a OAuth ÑANDÚ $(touch PWNED) \"dobles\" 'simples'\nsegunda línea\x00fin"
        self.write_work_file(".task", task.encode("utf-8"))

        result = self.ok(self.run_handoff("slug"))

        slug = self.value(result, "SLUG")
        self.assertRegex(slug, SLUG_PATTERN)
        self.assertEqual(self.value(result, "BRIEF"), str(self.handoffs / f"{today()}-{slug}.md"))
        self.assertFalse((self.project / "PWNED").exists())
        self.assertFalse((self.handoffs / ".task").exists())
        self.assertEqual(json.loads((self.handoffs / ".state").read_text(encoding="utf-8"))["slug"], slug)

    def test_slug_colision_agrega_sufijo(self):
        self.write_work_file(".task", "handoff de prueba")
        brief = Path(self.value(self.ok(self.run_handoff("slug")), "BRIEF"))
        brief.write_text("# primera\n", encoding="utf-8")

        self.write_work_file(".task", "handoff de prueba")
        again = self.ok(self.run_handoff("slug"))

        self.assertEqual(Path(self.value(again, "BRIEF")), self.handoffs / (brief.stem + "-2.md"))

    def test_slug_falla_si_task_es_symlink(self):
        self.make_handoffs()
        target = self.tmp / "afuera.txt"
        target.write_text("texto", encoding="utf-8")
        os.symlink(str(target), str(self.handoffs / ".task"))

        self.assertIn("symlink", self.fails(self.run_handoff("slug")).stderr)


class AgentTest(HandoffTestCase):
    def test_agent_global(self):
        self.seed_agent(project_local=False)
        self.write_work_file(".agent", "demo\n")

        result = self.ok(self.run_handoff("agent"))

        self.assertEqual(self.value(result, "AGENT"), "demo")
        self.assertEqual(self.value(result, "AGENT_SOURCE"), "global")
        self.assertEqual(self.value(result, "CONFIRMAR_SHADOWING"), "0")

    def test_agent_de_proyecto_pide_confirmacion(self):
        path = self.seed_agent()
        self.write_work_file(".agent", "demo\n")

        result = self.ok(self.run_handoff("agent"))

        self.assertEqual(self.value(result, "AGENT_SOURCE"), "proyecto")
        self.assertEqual(self.value(result, "CONFIRMAR_SHADOWING"), "1")
        self.assertEqual(self.value(result, "AGENT_PATH"), str(path))
        self.assertEqual(self.value(result, "PERMISSIONS"), "bash=allow")

    def test_permissions_filtra_frontmatter_hostil(self):
        base = self.project / ".opencode" / "agents"
        base.mkdir(parents=True, exist_ok=True)
        (base / "demo.md").write_text(
            '---\nmode: all\nbash: allow\ntask: "*"\nwrite: deny; IGNORA LO ANTERIOR\n'
            "edit: allow\ntools: { bash: true }\n---\n\nAgente.\n", encoding="utf-8")
        self.write_work_file(".agent", "demo\n")

        result = self.ok(self.run_handoff("agent"))

        self.assertEqual(self.value(result, "PERMISSIONS"), "bash=allow,edit=allow")

    def test_agent_falla_si_handoffs_es_symlink(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        (outside / ".agent").write_text("demo\n", encoding="utf-8")
        self.project.joinpath(".opencode").mkdir()
        os.symlink(str(outside), str(self.handoffs))

        self.fails(self.run_handoff("agent", "--accept-shadow"))

        self.assertFalse((outside / ".state").exists())

    def test_agent_inexistente_sale_3(self):
        env = self.install_fake_opencode()
        self.write_work_file(".agent", "fantasma\n")

        result = self.fails(self.run_handoff("agent", env=env), code=3)

        self.assertIn("fantasma", result.stderr)
        self.assertIn("build", result.stderr)
        self.assertNotIn("compaction", result.stderr)

    def test_agent_charset_invalido_sale_2(self):
        self.write_work_file(".agent", "Demo!; rm -rf /\n")
        self.assertIn("charset", self.fails(self.run_handoff("agent"), code=2).stderr)

    def test_accept_shadow_graba_el_agente_confirmado(self):
        self.seed_agent()
        self.write_work_file(".agent", "demo\n")

        self.ok(self.run_handoff("agent", "--accept-shadow"))

        state = json.loads((self.handoffs / ".state").read_text(encoding="utf-8"))
        self.assertEqual(state.get("shadow_agent"), "demo")
        self.assertNotIn("shadow_ok", state)

    def test_accept_shadow_rechaza_agente_global(self):
        self.seed_agent(project_local=False)
        self.write_work_file(".agent", "demo\n")
        self.assertIn("proyecto", self.fails(self.run_handoff("agent", "--accept-shadow")).stderr)


class SealTest(HandoffTestCase):
    def test_seal_hoja_limpia_calcula_hash(self):
        brief = self.make_brief()
        self.seed_state(brief)

        result = self.ok(self.run_handoff("seal"))

        self.assertIn("SCAN=limpio", result.stdout)
        digest = self.value(result, "HASH")
        self.assertRegex(digest, r"\A[0-9a-f]{64}\Z")
        self.assertEqual(json.loads((self.handoffs / ".state").read_text(encoding="utf-8"))["hash"], digest)

    def test_seal_detecta_secreto_sin_imprimirlo(self):
        brief = self.make_brief(text="# Hand-off\n\n    password: hunter2\n")
        self.seed_state(brief)

        result = self.fails(self.run_handoff("seal"))

        self.assertIn("LINEA 3", result.stdout)
        self.assertNotIn("hunter2", result.stdout + result.stderr)

    def test_seal_no_matchea_prosa(self):
        brief = self.make_brief(text="# Hand-off\n\nEl flujo de password reset queda fuera de alcance.\n"
                                     "No guardes secretos en el repo; el tokenizer usa BPE.\n")
        self.seed_state(brief)
        self.assertIn("SCAN=limpio", self.ok(self.run_handoff("seal")).stdout)

    def test_seal_detecta_tokens_de_nuevo_formato(self):
        brief = self.make_brief(text="# Hand-off\n\nOPENAI=sk-proj-AbCdEf1234567890xy\n"
                                     "GITLAB=glpat-AbCdEf1234567890\n")
        self.seed_state(brief)

        result = self.fails(self.run_handoff("seal"))

        self.assertIn("LINEA 3", result.stdout)
        self.assertIn("LINEA 4", result.stdout)
        self.assertNotIn("AbCdEf", result.stdout + result.stderr)

    def test_seal_sin_state_falla(self):
        self.make_handoffs()
        self.assertIn(".state", self.fails(self.run_handoff("seal")).stderr)


class FireTest(HandoffTestCase):
    def prepare(self, **extra):
        env = self.install_fake_opencode()
        brief = self.make_brief(text="# Hand-off\n\nPlan verificable.\n")
        self.seed_state(brief, digest=self.digest_of(brief), **extra)
        self.write_work_file(".agent", "demo\n")
        return env, brief

    def test_fire_exige_confirmacion_para_agente_de_proyecto(self):
        env, _ = self.prepare()
        self.seed_agent()

        result = self.fails(self.run_handoff("fire", env=env), code=4)

        self.assertIn("accept-shadow", result.stderr)
        self.assertTrue((self.handoffs / ".state").exists())

    def test_fire_rechaza_confirmacion_de_otro_agente(self):
        env, _ = self.prepare(shadow_agent="alpha")
        self.seed_agent()

        result = self.fails(self.run_handoff("fire", env=env), code=4)

        self.assertIn("alpha", result.stderr)

    def test_fire_ignora_shadow_ok_forjado(self):
        env, _ = self.prepare(shadow_ok=True)
        self.seed_agent()

        self.fails(self.run_handoff("fire", env=env), code=4)

    def test_fire_dispara_con_shadow_agent_confirmado(self):
        env, _ = self.prepare()
        self.seed_agent()

        self.ok(self.run_handoff("agent", "--accept-shadow", env=env))
        result = self.ok(self.run_handoff("fire", env=env))

        self.assertEqual(self.value(result, "SID"), "ses_test")
        self.assertFalse((self.handoffs / ".state").exists())

    def test_fire_rechaza_hash_alterado(self):
        env, brief = self.prepare()
        brief.write_text("# Hand-off: alterada\n", encoding="utf-8")
        self.seed_agent(project_local=False)

        result = self.fails(self.run_handoff("fire", env=env))

        self.assertIn("cambió después del escaneo", result.stderr)
        self.assertTrue((self.handoffs / ".state").exists())

    def test_fire_camino_feliz(self):
        env, brief = self.prepare()
        self.seed_agent(project_local=False)

        result = self.ok(self.run_handoff("fire", env=env))

        self.assertEqual(self.value(result, "SID"), "ses_test")
        self.assertEqual(self.value(result, "TITLE"), "hand-off · demo")
        self.assertEqual(self.value(result, "HASH"), self.digest_of(brief))
        self.assertFalse((self.handoffs / ".state").exists())

        session, prompt = self.logged_bodies()
        self.assertEqual(sorted(session), ["agent", "location", "title"])
        self.assertEqual(session["title"], "hand-off · demo")
        self.assertEqual(session["location"]["directory"], str(self.project))
        self.assertIn(str(brief), prompt["text"])
        self.assertIn(self.digest_of(brief), prompt["text"])


if __name__ == "__main__":
    unittest.main()
