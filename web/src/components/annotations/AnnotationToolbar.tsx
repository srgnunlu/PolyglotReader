'use client';

import { useAnnotations } from '@/contexts/AnnotationContext';
import { AnnotationType } from '@/types/models';
import styles from './AnnotationToolbar.module.css';

const COLORS = [
    { name: 'Yellow', value: '#fef08a' },
    { name: 'Green', value: '#bbf7d0' },
    { name: 'Blue', value: '#bae6fd' },
    { name: 'Pink', value: '#fbcfe8' },
];

const TOOLS: { name: string; type: AnnotationType; icon: string }[] = [
    { name: 'Highlight', type: 'highlight', icon: '🖍️' },
    { name: 'Underline', type: 'underline', icon: '⎯' },
    { name: 'Strikethrough', type: 'strikethrough', icon: '~~' },
];

export function AnnotationToolbar() {
    const { selectedTool, selectedColor, setSelectedTool, setSelectedColor } = useAnnotations();

    return (
        <div className={styles.toolbar}>
            <div className={styles.section}>
                <span className={styles.label}>Tool:</span>
                {TOOLS.map(tool => (
                    <button
                        key={tool.type}
                        className={`${styles.toolBtn} ${selectedTool === tool.type ? styles.active : ''}`}
                        onClick={() => setSelectedTool(selectedTool === tool.type ? null : tool.type)}
                        title={tool.name}
                    >
                        {tool.icon}
                    </button>
                ))}
            </div>

            {selectedTool && (
                <div className={styles.section}>
                    <span className={styles.label}>Color:</span>
                    {COLORS.map(color => (
                        <button
                            key={color.value}
                            className={`${styles.colorBtn} ${selectedColor === color.value ? styles.active : ''}`}
                            onClick={() => setSelectedColor(color.value)}
                            style={{ backgroundColor: color.value }}
                            title={color.name}
                        />
                    ))}
                </div>
            )}
        </div>
    );
}
