# Godot Snippeteer Plugin

Adds functionality to replace keywords with parameterized code snippets.

**Features:**
- In-editor snippet management  
- Multi-caret parameters  
- Explicit cursor placement  
- It likes cats 😺

## Usage

After enabling the plugin, you should see a "Snippet" tab in the Inspector dock.  
There, you can easily add, edit, and save all your snippets.

If you type a snippet keyword and press the configured snippet key (default: *Tab*), the keyword will be replaced by the snippet, and all occurrences of the first defined parameter will be selected.  
Each subsequent press of the snippet key jumps to the next parameter occurrence.  
Finally, it jumps to the defined caret position (**|**) or, if none is defined, to the end of the snippet text.

Just like you're used to from other popular editors.

## Snippets

Snippets are simply the text that should replace a keyword.  
You can add parameter placeholders using **$1**, **$2**, ... and define a final caret position with **|**.
