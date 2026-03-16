'use client';

import { useState, useRef, useCallback, useEffect, type RefObject } from 'react';

interface UseDraggableOptions {
    initialPosition: { x: number; y: number };
    boundaryRef?: RefObject<HTMLElement | null>;
    enabled?: boolean;
}

interface DragHandleProps {
    onMouseDown: (e: React.MouseEvent) => void;
    onTouchStart: (e: React.TouchEvent) => void;
    style: { cursor: string };
}

interface UseDraggableReturn {
    position: { x: number; y: number };
    setPosition: (pos: { x: number; y: number }) => void;
    isDragging: boolean;
    dragHandleProps: DragHandleProps;
}

export function useDraggable({
    initialPosition,
    boundaryRef,
    enabled = true,
}: UseDraggableOptions): UseDraggableReturn {
    const [position, setPosition] = useState(initialPosition);
    const [isDragging, setIsDragging] = useState(false);
    const dragStart = useRef({ x: 0, y: 0 });
    const positionAtDragStart = useRef({ x: 0, y: 0 });

    // Update position when initialPosition changes (e.g. sticky to selection)
    const prevInitial = useRef(initialPosition);
    useEffect(() => {
        if (
            !isDragging &&
            (prevInitial.current.x !== initialPosition.x || prevInitial.current.y !== initialPosition.y)
        ) {
            setPosition(initialPosition);
            prevInitial.current = initialPosition;
        }
    }, [initialPosition, isDragging]);

    const clampToBounds = useCallback(
        (x: number, y: number) => {
            if (!boundaryRef?.current) return { x, y };
            const bounds = boundaryRef.current.getBoundingClientRect();
            return {
                x: Math.max(0, Math.min(bounds.width, x)),
                y: Math.max(0, Math.min(bounds.height, y)),
            };
        },
        [boundaryRef]
    );

    const handleDragMove = useCallback(
        (e: MouseEvent | TouchEvent) => {
            const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
            const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;

            const dx = clientX - dragStart.current.x;
            const dy = clientY - dragStart.current.y;

            const newPos = clampToBounds(
                positionAtDragStart.current.x + dx,
                positionAtDragStart.current.y + dy
            );
            setPosition(newPos);
        },
        [clampToBounds]
    );

    const handleDragEnd = useCallback(() => {
        setIsDragging(false);
        document.removeEventListener('mousemove', handleDragMove);
        document.removeEventListener('touchmove', handleDragMove);
        document.removeEventListener('mouseup', handleDragEnd);
        document.removeEventListener('touchend', handleDragEnd);
    }, [handleDragMove]);

    const handleDragStart = useCallback(
        (e: React.MouseEvent | React.TouchEvent) => {
            if (!enabled) return;
            e.preventDefault();
            setIsDragging(true);

            const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
            const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;

            dragStart.current = { x: clientX, y: clientY };
            positionAtDragStart.current = { ...position };

            document.addEventListener('mousemove', handleDragMove);
            document.addEventListener('touchmove', handleDragMove);
            document.addEventListener('mouseup', handleDragEnd);
            document.addEventListener('touchend', handleDragEnd);
        },
        [enabled, position, handleDragMove, handleDragEnd]
    );

    // Cleanup on unmount
    useEffect(() => {
        return () => {
            document.removeEventListener('mousemove', handleDragMove);
            document.removeEventListener('touchmove', handleDragMove);
            document.removeEventListener('mouseup', handleDragEnd);
            document.removeEventListener('touchend', handleDragEnd);
        };
    }, [handleDragMove, handleDragEnd]);

    const dragHandleProps: DragHandleProps = {
        onMouseDown: handleDragStart,
        onTouchStart: handleDragStart,
        style: { cursor: isDragging ? 'grabbing' : 'grab' },
    };

    return { position, setPosition, isDragging, dragHandleProps };
}
