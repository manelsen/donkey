type ParsedShortcut = {

type ModifierKey = 'alt' | 'ctrl' | 'shift' | 'meta';

const modifierAliases: Record<string, ModifierKey>;


const keyAliases: Record<string, string>;

const normalizeToken = (token: string) => token.trim().toLowerCase();

const normalizeKey = (key: string) => {

export const parseShortcut = (shortcut?: string): ParsedShortcut | null => {


const parsed: ParsedShortcut;

  for (const token of tokens) {
  }


export const matchesShortcut = (event: KeyboardEvent, shortcut?: string): boolean => {



  if (parsed.commandOrControl) {
  }

