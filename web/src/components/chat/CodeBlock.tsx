'use client';

import { useState } from 'react';
import { Highlight, themes } from 'prism-react-renderer';
import styles from './CodeBlock.module.css';

interface CodeBlockProps {
    children: string;
    language?: string;
}

export function CodeBlock({ children, language = '' }: CodeBlockProps) {
    const [copied, setCopied] = useState(false);

    const handleCopy = async () => {
        await navigator.clipboard.writeText(children);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
    };

    return (
        <div className={styles.codeBlock}>
            <div className={styles.codeHeader}>
                <span className={styles.codeLang}>{language || 'code'}</span>
                <button className={styles.copyBtn} onClick={handleCopy}>
                    {copied ? 'Kopyalandı!' : 'Kopyala'}
                </button>
            </div>
            <Highlight theme={themes.oneDark} code={children.trim()} language={language || 'text'}>
                {({ style, tokens, getLineProps, getTokenProps }) => (
                    <pre className={styles.codeContent} style={style}>
                        {tokens.map((line, i) => (
                            <div key={i} {...getLineProps({ line })}>
                                <span className={styles.lineNumber}>{i + 1}</span>
                                {line.map((token, key) => (
                                    <span key={key} {...getTokenProps({ token })} />
                                ))}
                            </div>
                        ))}
                    </pre>
                )}
            </Highlight>
        </div>
    );
}
