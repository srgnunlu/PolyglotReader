import { getSupabase } from './supabase';
import { Annotation, DatabaseAnnotation, AnnotationType, AnnotationRect } from '@/types/models';

/**
 * Converts database annotation format (mobile schema) to client Annotation format
 * Mobile uses 'page' column and nested 'data' JSONB column
 */
function dbToAnnotation(db: DatabaseAnnotation): Annotation {
    return {
        id: db.id,
        fileId: db.file_id,
        pageNumber: db.page,  // Mobile uses 'page', not 'page_number'
        type: db.type as AnnotationType,
        color: db.data.color,
        rects: db.data.rects || [],
        text: db.data.text,
        note: db.data.note,
        isAiGenerated: db.data.isAiGenerated ?? false,
        createdAt: new Date(db.created_at),
    };
}

/**
 * Load all annotations for a specific file
 */
export async function loadAnnotations(fileId: string): Promise<Annotation[]> {
    const supabase = getSupabase();

    const { data, error } = await supabase
        .from('annotations')
        .select('*')
        .eq('file_id', fileId)
        .order('page', { ascending: true });  // Mobile uses 'page' column

    if (error) {
        console.error('❌ Error loading annotations:', error);
        return [];
    }

    return (data || []).map(dbToAnnotation);
}

/**
 * Save a new annotation to Supabase (matching mobile schema)
 */
export async function saveAnnotation(
    fileId: string,
    pageNumber: number,
    type: AnnotationType,
    color: string,
    rects: AnnotationRect[],
    text?: string,
    note?: string
): Promise<Annotation | null> {
    const supabase = getSupabase();

    // Get current user for user_id
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
        console.error('❌ Error saving annotation: No authenticated user');
        return null;
    }

    // Generate UUID for the annotation
    const annotationId = crypto.randomUUID();

    // Mobile schema uses 'page' column and 'data' JSONB column
    const { data, error } = await supabase
        .from('annotations')
        .insert({
            id: annotationId,  // Required: database doesn't auto-generate
            file_id: fileId,
            user_id: user.id,
            page: pageNumber,  // Mobile uses 'page', not 'page_number'
            type,
            data: {
                color,
                rects,
                text,
                note,
                isAiGenerated: false,
            },
        })
        .select()
        .single();

    if (error) {
        console.error('❌ Error saving annotation:', error);
        return null;
    }

    return data ? dbToAnnotation(data) : null;
}

/**
 * Update an existing annotation (matching mobile schema with nested data JSONB)
 */
export async function updateAnnotation(
    annotationId: string,
    updates: Partial<Pick<Annotation, 'color' | 'note' | 'text'>>
): Promise<boolean> {
    const supabase = getSupabase();

    // Since data is a JSONB column, we need to fetch-modify-update
    // 1. Fetch existing annotation
    const { data: existing, error: fetchError } = await supabase
        .from('annotations')
        .select('*')
        .eq('id', annotationId)
        .single();

    if (fetchError || !existing) {
        console.error('❌ Error fetching annotation for update:', fetchError);
        return false;
    }

    // 2. Merge updates into data object
    const updatedData = {
        ...existing.data,
        ...(updates.color !== undefined && { color: updates.color }),
        ...(updates.note !== undefined && { note: updates.note }),
        ...(updates.text !== undefined && { text: updates.text }),
    };

    // 3. Update with new data
    const { error } = await supabase
        .from('annotations')
        .update({ data: updatedData })
        .eq('id', annotationId);

    if (error) {
        console.error('❌ Error updating annotation:', error);
        return false;
    }

    return true;
}

/**
 * Delete an annotation
 */
export async function deleteAnnotation(annotationId: string): Promise<boolean> {
    const supabase = getSupabase();

    const { error } = await supabase
        .from('annotations')
        .delete()
        .eq('id', annotationId);

    if (error) {
        console.error('❌ Error deleting annotation:', error);
        return false;
    }

    return true;
}

/**
 * Delete all annotations for a file
 */
export async function clearAllAnnotations(fileId: string): Promise<boolean> {
    const supabase = getSupabase();

    const { error } = await supabase
        .from('annotations')
        .delete()
        .eq('file_id', fileId);

    if (error) {
        console.error('❌ Error clearing annotations:', error);
        return false;
    }

    return true;
}
