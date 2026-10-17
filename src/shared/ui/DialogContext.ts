import { createContext } from "react";

/** Menus retain their modal's context when they portal outside its DOM. */
export const InDialog = createContext(false);
