import type { RuntimeEnv } from "../runtime.js";
import { defaultRuntime } from "../runtime.js";
import type { WizardSection } from "./configure.shared.js";
import { CONFIGURE_WIZARD_SECTIONS, parseConfigureWizardSections } from "./configure.shared.js";
import { runConfigureWizard } from "./configure.wizard.js";
export async function configureCommand(runtime: RuntimeEnv = defaultRuntime);
export async function configureCommandWithSections(;
export async function configureCommandFromSectionsArg(;
